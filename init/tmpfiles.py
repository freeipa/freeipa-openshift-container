#!/bin/python3

"""

Script that processes systemd-tmpfiles config files, approximately
in the manner described by `tmpfiles.d(5)`.

Only creates files/dirs/links, chowns, chmods, sets attributes and
ACLs.  Does not implement cleanup and removal.

`!` (indicating post-boot unsafety) is ignored, because this script
is only intended to be used at container startup.

ONLY files in `/usr/lib/tmpfiles.d` are read - not the other
directories.  Does not perform any conflict resolution (where the
same target file is mentioned by multiple config files).

"""

import argparse
import collections
import glob
import grp
import itertools
import operator
import os
import pathlib
import pwd
import re
import shutil
import stat
import subprocess
import sys
import tempfile

TMPFILES_DIRS = (
    "/etc/tmpfiles.d",
    "/run/tmpfiles.d",
    "/usr/lib/tmpfiles.d"
)
FACTORY_DIR = "/usr/share/factory"
BOOT_ID_FILE = "/proc/sys/kernel/random/boot_id"
MACHINE_ID_FILE = "/etc/machine-id"


def list_tmpfiles_configs():
    """Return sorted list of absolute paths to tmpfiles configs.

    Files are searched in /etc, /run, and /usr directories. File names
    /etc takes precedence over /run and /usr.
    """
    seen = set()
    conffiles = []
    for confdir in TMPFILES_DIRS:
        try:
            candidates = os.listdir(confdir)
        except (NotADirectoryError, FileNotFoundError):
            continue
        for conffile in candidates:
            if not conffile.endswith(".conf"):
                continue
            if conffile in seen:
                continue
            seen.add(conffile)
            conffiles.append(os.path.join(confdir, conffile))
    # sort by file name, no matter which directory the file resides in.
    conffiles.sort(key=os.path.basename)
    return conffiles


def get_specifier_map():
    """Create mapping from specifier to value"""
    # $TMPDIR, $TEMP, $TMP, or /tmp
    tmpdir = tempfile.gettempdir()

    # specifier_user_id() calls getuid(), not geteuid()
    uid = os.getuid()
    username = pwd.getpwuid(uid).pw_name
    gid = os.getgid()
    groupname = grp.getgrgid(gid).gr_name

    uname = os.uname()
    # machine is "x86_64", systemd wants "x86-64"
    arch = uname.machine.replace("_", "-")
    hostname = uname.nodename
    shortname = hostname.split(".", 1)[0]

    with open(BOOT_ID_FILE) as f:
        # Kernel boot_id file has dashes, systemd strips dashes
        boot_id = f.read().strip().replace("-", "")

    with open(MACHINE_ID_FILE) as f:
        machine_id = f.read().strip()

    return {
        "a": arch,  # architecture
        # "A": None,  # os-release IMAGE_VERSION or empty string
        "b": boot_id,
        # "B": None,  # os-release BUILD_ID or empty string
        "C": "/var/cache",  # system cache dir
        "g": groupname,  # user group name
        "G": str(gid),  # user gid
        "h": "/root",  # home dir
        "H": hostname,  # node host name
        "l": shortname,  # short host name
        "L": "/var/log",  # system log dir
        "m": machine_id,  # /etc/machine-id
        # "M": None,  # os-release IMAGE_ID or empty string
        # "o": None,  # os-release ID, never empty string (!)
        "S": "/var/lib",  # system state dir
        "t": "/run",  # system runtime dir
        "T": tmpdir,  # system tmp dir
        "u": username,  # user name
        "U": str(uid),  # uid
        "v": uname.release,  # Kernel release (uname -r)
        "V": "/var/run",  # large file tmp dir
        # "w": None,  # os-release VERSION_ID or empty string
        # "W": None,  # os-release VARIANT_ID or empty string
        "%": "%",  # %% -> %
    }


SPECIFIERS = get_specifier_map()


def resolve_specifiers(path):
    """Substitute specifiers in a path (%b, %m, ...)"""
    if "%" not in path:  # fast path
        return path

    def subst_cb(mo):
        spec = mo.group(1)
        try:
            return SPECIFIERS[spec]
        except KeyError:
            raise ValueError(f"Unsupported specififer '{spec}' in '{path}'.")

    return re.sub(r"%([a-zA-Z%])", subst_cb, path)


def read_tmpfiles_config(path, prefix):
    """
    Read the tmpfiles config.  Return a `list` of groups of
    `(path,list_of_actions)` tuples, with paths in lexicographic
    order.  Therefore, prefix/parent paths are always listed before
    suffix/child paths.

    Ignore paths that do not match the given `prefix`.

    """
    with open(path) as f:
        lines = f.readlines()
    actions = (
        parse_action(line.strip())
        for line in lines
        if len(line.strip()) > 0 and not line.startswith("#")
    )

    # filter out paths that do not match prefix
    prefix_Path = pathlib.Path(prefix)

    def matches_prefix(s):
        s_Path = pathlib.Path(s)
        return prefix_Path in [s_Path, *s_Path.parents]

    actions = (
        (path, action) for path, action in actions if matches_prefix(path)
    )

    # putting things in order.
    #
    # pass 1: sort all actions by path.
    #         output is iterable of (path, action)
    #
    actions = sorted(actions, key=operator.itemgetter(0))

    # pass 2: group actions by path.
    #         output is iterable of (path, [(path, action)])
    actions = itertools.groupby(actions, key=operator.itemgetter(0))

    # pass 2.1: discard redundant path, dissolve nested tuple.
    #           output is iterable of (path, [action])
    actions = ((k, map(operator.itemgetter(1), v)) for k, v in actions)

    # pass 3: sort actions for each path
    ACTION_ORDER = list(ACTION_MAP.values())

    def f(action):
        return ACTION_ORDER.index(type(action))

    actions = ((path, sorted(l, key=f)) for path, l in actions)

    # finally, return a list (makes debugging easier)
    return list(actions)


def parse_action(line):
    """
    Parse a line, returning a `(path,action)` pair or raising
    ValueError on parse failure.  This function should NOT be
    applied to empty lines or comments.
    """
    fields = line.split(maxsplit=6)
    fields += [None] * (7 - len(fields))  # extend to required length
    typ, path, mode, user, group, age, arg = fields

    # apply templating, e.g. %b
    path = resolve_specifiers(path)

    boot_only = "!" in typ
    ignore_error = "-" in typ  # TODO implement
    remove_mismatched = "=" in typ  # TODO implement
    typ = typ.strip("!-=")

    action = ACTION_MAP[typ](boot_only, mode, user, group, age, arg)
    return (path, action)


def main():
    parser = argparse.ArgumentParser(description="systemd-tmpfiles clone")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--create", action="store_true")
    parser.add_argument("--remove", action="store_true")
    parser.add_argument("--clean", action="store_true")
    parser.add_argument("--prefix", default="/")
    args = parser.parse_args()

    if not any([args.create, args.remove, args.clean]):
        sys.exit("Must specify one or more of --create, --remove, --clean")
    if args.remove:
        sys.exit("--remove is not implemented")
    if args.clean:
        sys.exit("--clean is not implemented")

    config_files = list_tmpfiles_configs()
    for config_file in config_files:
        for path, actions in read_tmpfiles_config(config_file, args.prefix):
            print(f">>> {path}")
            for action in actions:
                if args.dry_run:
                    print(action)
                else:
                    if args.create:
                        action.apply(path)


def _parse_mode(s):
    if s is None:
        return None

    mask = False
    if s.startswith("~"):
        mask = True
        s = s[1:]

    return (mask, int(s, base=8))


def _parse_user(s):
    if s is None:
        return None
    try:
        return int(s)
    except ValueError:
        return pwd.getpwnam(s)[2]


def _parse_group(s):
    if s is None:
        return None
    try:
        return int(s)
    except ValueError:
        return grp.getgrnam(s)[2]


def _parse_attrs(s):
    if not s:  # None or empty string
        raise ValueError("file attributes cannot be empty")
    if s[0] not in "+-=":
        s = "+" + s  # default operation is '+'

    # TODO more complete checks?  For now just take it as-is.
    return s


def _parse_acls(s):
    if not s:  # None or empty string
        raise ValueError("file ACLs cannot be empty")

    # TODO more checks?
    return s


def _parse_major_minor(s):
    if s is None:
        raise ValueError("major:minor cannot be empty")

    parts = s.split(":")
    if len(parts) != 2:
        raise ValueError("major:minor must have 2 parts")

    try:
        major = int(parts[0])
        minor = int(parts[1])
    except ValueError:
        raise ValueError("major:minor must be integers")

    return (major, minor)


def _run_process(desc, args):
    try:
        subprocess.check_call(args)
    except FileNotFoundError:
        if len(args) < 1:
            prog = "<undefined>"
        else:
            prog = args[0]
        print(f"failed to {desc}: {prog!r} program not found")
    except subprocess.CalledProcessError as e:
        print(f"failed to {desc}: {e}")


class Action:
    # function to parse/massage argument value
    # If should raise ValueError for invalid input.
    arg_function = staticmethod(lambda x: x)

    def __init__(self, bootonly, mode, user, group, age, arg):
        self.bootonly = bootonly
        self._set("mode", mode, function=_parse_mode)
        self._set("user", user, function=_parse_user)
        self._set("group", group, function=_parse_group)
        self._set("age", age, function=lambda TODO: TODO)
        self._set("arg", arg, function=self.arg_function)

    def _set(self, k, v, function=lambda x: x):
        if v == "-":
            v = None
        setattr(self, k, function(v))

    def describe(self, path):
        """Describe the action."""
        raise NotImplementedError

    def apply(self, path):
        """Apply the action."""
        self.apply_one(path)

    def apply_one(self, path):
        """
        Apply the action on a single path.

        This function may be called an arbitrary number of times
        (including zero) for glob-based actions.

        """
        raise NotImplementedError

    def _chown_and_chmod(self, path):
        # the order matters, because chown(2) resets SUID and SGID bits
        self._chown(path)
        self._chmod(path)

    def _chmod(self, path):
        """Set the file mode.  Caller must ensure file exists."""
        if self.mode is None:
            mask = False
            if os.path.islink(path) or not os.path.isdir(path):
                mode = 0o644  # is a file or symbolic link
            else:
                mode = 0o755  # is a dir
        else:
            mask, mode = self.mode

        if mask:
            r = os.lstat(path).st_mode  # stat file

            # existing mode masks new mode
            mode &= stat.S_IMODE(r)

            # unset sticky/SUID/SGID unless directory
            if not stat.S_ISDIR(r):
                mode &= ~(stat.S_ISUID | stat.S_ISGID | stat.S_ISVTX)

        try:
            os.chmod(path, mode, follow_symlinks=False)
        except:
            print(f"failed to chmod {path!r}")

    def _chown(self, path):
        """Set the file ownership.  Caller must ensure file exists."""
        user = self.user
        if user is None:
            user = -1
        group = self.group
        if group is None:
            group = -1
        if user >= 0 or group >= 0:
            try:
                os.chown(path, user, group, follow_symlinks=False)
            except:
                print(f"failed to chmod {path!r}")


class GlobAction(Action):
    """Action that takes a glob rather than a path."""

    def apply(self, pattern):
        for path in glob.glob(pattern):
            self.apply_one(path)


class FileCreate(Action):
    """f - create file with optional content"""

    def apply_one(self, path):
        if not os.path.lexists(path):
            with open(path, "w") as f:
                f.write(self.arg if self.arg is not None else "")
        self._chown_and_chmod(path)


class FileCreateOrTruncate(Action):
    """f+ - create or truncate file, with optional content"""

    def apply_one(self, path):
        with open(path, "w") as f:
            f.write(self.arg if self.arg is not None else "")
        self._chown_and_chmod(path)


class FileWrite(GlobAction):
    """w - write to file"""

    # TODO interpret C-style blackslashes in argument.  Also for
    # other actions (f, f+, w+, ...)
    def apply_one(self, path):
        with open(path, "w") as f:
            f.write(self.arg if self.arg is not None else "")
        self._chown_and_chmod(path)


class FileAppend(GlobAction):
    """w+ - append to file"""

    def apply_one(self, path):
        with open(path, "a") as f:
            f.write(self.arg if self.arg is not None else "")
        self._chown_and_chmod(path)


class DirCreateAndCleanup(Action):
    """d - create and cleanup directory"""

    def apply_one(self, path):
        if not os.path.lexists(path):
            os.makedirs(path)
        self._chown_and_chmod(path)


class DirCreateAndRemove(DirCreateAndCleanup):
    """D - create and remove directory"""

    # No additional behaviour, until --remove gets implemented


class DirCleanup(GlobAction):
    """e - create and remove directory"""

    def apply_one(self, path):
        if os.path.isdir(path):
            self._chown_and_chmod(path)


class SubvolumeCreate_v(DirCreateAndCleanup):
    """v - create subvolume or directory"""

    # ignore subvolume behaviour


class SubvolumeCreate_q(DirCreateAndCleanup):
    """q - create subvolume or directory"""

    # ignore subvolume behaviour


class SubvolumeCreate_Q(DirCreateAndCleanup):
    """Q - create subvolume or directory"""

    # ignore subvolume behaviour


# TODO p, p+


class SymlinkCreate(Action):
    """L - create symlink"""

    def apply_one(self, path):
        # only create symlink if it does not exists yet
        # don't care about existing but broken links
        if not os.path.exists(path) and not os.path.islink(path):
            if self.arg is None:
                # TODO link to /usr/share/factory/FILE
                # (see tmpfiles.d(5) for details)
                raise RuntimeError("symlink target not specified")
            os.symlink(self.arg, path)


class SymlinkRecreate(SymlinkCreate):
    """L+ - [re]create symlink"""

    def apply_one(self, path):
        # need to detect if path is broken link, because
        # os.path.exists returns False for broken symbolic links
        if os.path.exists(path) or os.path.islink(path):
            if not os.path.islink(path) and os.path.isdir(path):
                # remove directory with all its content
                shutil.rmtree(path)
            else:
                # remove existing file or link (but not target file)
                os.unlink(path)
        super().apply(path)


class CreateCharDev(Action):
    """c - create character device node"""

    arg_function = staticmethod(_parse_major_minor)

    def apply_one(self, path):
        major, minor = self.args
        if not os.path.lexists():
            _run_process(
                f"create character device at {path}",
                ["mknod", path, c, major, minor],
            )


# TODO c+ b b+ (char and block devices)


class Copy(Action):
    """C - copy file"""

    def apply_one(self, path):
        src = self.arg
        if src is None:
            src = os.path.join(FACTORY_DIR, os.path.relpath(path, start="/"))

        # if path is a symlink, resolve it
        if os.path.islink(path):
            path = os.path.join(os.path.dirname(path), os.readlink(path))

        # ensure intermediate directories exist
        if not os.path.isdir(os.path.dirname(path)):
            os.makedirs(os.path.dirname(path))

        if os.path.islink(src) or not os.path.isdir(src):
            if not os.path.exists(path):
                shutil.copy(src, path, follow_symlinks=False)
        else:  # src is a directory
            if (
                os.path.isdir(path)
                and not os.path.islink(path)
                and len(os.listdir(path)) <= 0
            ):
                # dst is a empty dir.  remove it (it will be recreated)
                os.rmdir(path)
            if not os.path.exists(path):
                shutil.copytree(src, path, symlinks=True)


class IgnoreRecursive(GlobAction):
    """x - ignore path or glob recursively"""

    def apply_one(_self, _path):
        pass  # nothing to due; only applies to cleanup


class Ignore(GlobAction):
    """X - ignore path or glob"""

    def apply_one(_self, _path):
        pass  # nothing to due; only applies to cleanup


class Remove(GlobAction):
    """r - remove empty dir"""

    def apply_one(self, path):
        if os.path.islink(path) or not os.path.isdir(path):
            os.unlink(path)
        elif len(os.listdir(path)) <= 0:
            os.rmdir(path)


class RemoveRecursive(GlobAction):
    """R - recursive delete"""

    def apply_one(self, path):
        if os.path.islink(path) or not os.path.isdir(path):
            os.unlink(path)
        else:
            shutil.rmtree(path, ignore_errors=True)


# TODO t T


class ModeAdjust(GlobAction):
    """z - adjust mode/user/group"""

    def apply_one(self, path):
        if os.path.lexists(path):
            self._chown_and_chmod(path)
            # TODO restore SELinux context


class ModeAdjustRecursive(GlobAction):
    """Z - adjust mode/user/group recursively"""

    def apply_one(self, path):
        if os.path.islink(path) or not os.path.isdir(path):
            # link or file
            self._chown_and_chmod(path)
            # TODO restore SELinux context
        else:  # directory
            for dirname, dirs, files in os.walk(path):
                for filename in dirs + files:
                    node = os.path.join(dirname, filename)
                    self._chown_and_chmod(path)
                    # TODO restore SELinux context


class AttrsSet(GlobAction):
    """h - set file attributes"""

    arg_function = staticmethod(_parse_attrs)
    chattr_args = []

    def apply_one(self, path):
        _run_process(
            f"change attributes of {path}",
            ["chattr"] + self.chattr_args + [self.arg, path],
        )


class AttrsSetRecursive(AttrsSet):
    """H - set file attributes recursively"""

    chattr_args = ["-R"]


class ACLsSet(GlobAction):
    """a - set POSIX ACLs"""

    arg_function = staticmethod(_parse_acls)

    def apply_one(self, path):
        _run_process(
            f"clear ACLs of {path}",
            ["setfacl", "--remove-all", "--", path],
        )
        _run_process(
            f"set ACLs of {path}",
            ["setfacl", "--modify", self.arg, "--", path],
        )


class ACLsAppend(GlobAction):
    """a+ - append POSIX ACLs"""

    arg_function = staticmethod(_parse_acls)

    def apply_one(self, path):
        _run_process(
            f"set ACLs of {path}",
            ["setfacl", "--modify", self.arg, "--", path],
        )


class ACLsSetRecursive(GlobAction):
    """A - set POSIX ACLs recursively"""

    arg_function = staticmethod(_parse_acls)

    def apply_one(self, path):
        _run_process(
            f"clear ACLs (recursively) of {path}",
            ["setfacl", "--recursive", "--remove-all", "--", path],
        )
        _run_process(
            f"set ACLs (recursively) of {path}",
            [
                "setfacl",
                "--recursive",
                "--physical",
                "--modify",
                self.arg,
                "--",
                path,
            ],
        )


class ACLsAppendRecursive(GlobAction):
    """A+ - append POSIX ACLs recursively"""

    arg_function = staticmethod(_parse_acls)

    def apply_one(self, path):
        _run_process(
            f"set ACLs (recursively) of {path}",
            [
                "setfacl",
                "--recursive",
                "--physical",
                "--modify",
                self.arg,
                "--",
                path,
            ],
        )


"""
Map of action type string to class.

This is an OrderedDict so that the insertion order determines the
order in which actions on the same path shall be performed.  An
example of why this is needed is that a file must be created
before you can set attributes, ACLs, etc.

The order is the order in which they appear in tmpfiles.d(5).  The
order seems reasonable, although I'm not sure whether it is the
order that systemd-tmpfiles actually uses.

TODO: % specifiers (at least %b and %m are required)

"""
ACTION_MAP = collections.OrderedDict(
    [
        ("f", FileCreate),
        ("f+", FileCreateOrTruncate),
        ("F", FileCreateOrTruncate),  # deprecated alias
        ("w", FileWrite),
        ("w+", FileAppend),
        ("d", DirCreateAndCleanup),
        ("D", DirCreateAndRemove),
        ("e", DirCleanup),
        ("v", SubvolumeCreate_v),
        ("q", SubvolumeCreate_q),
        ("Q", SubvolumeCreate_Q),
        ("L", SymlinkCreate),
        ("L+", SymlinkRecreate),
        ("c", CreateCharDev),
        ("C", Copy),
        ("x", IgnoreRecursive),
        ("X", Ignore),
        ("r", Remove),
        ("R", RemoveRecursive),
        ("z", ModeAdjust),
        ("m", ModeAdjust),  # deprecated alias
        ("Z", ModeAdjustRecursive),
        ("h", AttrsSet),
        ("H", AttrsSetRecursive),
        ("a", ACLsSet),
        ("a+", ACLsAppend),
        ("A", ACLsSetRecursive),
        ("A+", ACLsAppendRecursive),
    ]
)


if __name__ == "__main__":
    main()
