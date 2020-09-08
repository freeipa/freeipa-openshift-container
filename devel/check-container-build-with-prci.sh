#!/bin/bash

##
# Build the container using RPMs from a specified repository.
# Supported repository sources are PR-CI and COPR.
#
# Usage:
#
#   ARTIFACT_HASH="c8dbfc76-c4eb-11ea-88a6-fa163e90bd6d" ./devel/check-container-build-with-prci.sh
#
#   or
#
#   COPR_REPO=https://.../user-project-fedora-32.repo ./devel/check-container-build-with-prci.sh
##

ARTIFACT_HASH_FILENAME="artifact-hash.txt"
LATEST_FEDORA="fedora-32"

function yield
{
    echo "$*" >&2
} # yield


function error-msg
{
    yield "ERROR:$*"
} # error-msg


function die
{
    local err=$?
    [ $err -eq 0 ] && err=127
    error-msg "${FUNCNAME[1]}:$*"
    exit $err
} # die


function print-build-system
{
    local artifact_hash
    local url
    local build_system

    artifact_hash="$1"
    shift 1

    url="http://freeipa-org-pr-ci.s3-website.eu-central-1.amazonaws.com/jobs/${artifact_hash}/metadata.json"
    build_system="$( curl -s -L "${url}" | jq -r .task_name )"
    build_system="${build_system%%/*}"

    case "${build_system}" in
        "fedora-latest" )
            printf "%s\n" "${LATEST_FEDORA}"
            ;;
        "fedora-31" \
        | "fedora-32" )
            printf "%s\n" "${build_system}"
            ;;
        * )
            die "'${build_system}' system unsupported"
            ;;
    esac
} # print-build-system


function is-patched-dockerfile
{
    local dockerfilepath
    dockerfilepath="$1"
    grep -q "/etc/yum.repos.d/freeipa-development.repo" "${dockerfilepath}"
} # is-patched-dockerfile


function patch-dockerfile
{
    local dockerfilepath
    local repofilepath

    dockerfilepath="$1"
    repofilepath="$2"
    [ -e "${repofilepath}" ] || die "'${repofilepath}' .repo file can not be found."
    [ -e "${dockerfilepath}" ] || die "'${dockerfilepath}' Dockerfile file can not be found."

    is-patched-dockerfile "${dockerfilepath}" && return 0 # Nothing to do

    mapfile -t lines < "${dockerfilepath}"
    true > "${dockerfilepath}"
    for line in "${lines[@]}"
    do
        if [[ "${line}" =~ ^FROM\ * ]]
        then
            printf "%s\n" "${line}" >> "${dockerfilepath}"
            printf "COPY \"%s\" \"%s\"" "${repofilepath}" "/etc/yum.repos.d/freeipa-development.repo" >> "${dockerfilepath}"
        else
            printf "%s\n" "${line}" >> "${dockerfilepath}"
        fi
    done
} # patch-dockerfile


function clone-repository
{
    local repo_url
    repo_url="$1"

    [ -e "repo" ] || git clone --depth 1 -b master "${repo_url}" repo
} # clone-repository


[ ! -e .git ] && die "This script should be used from the repository root path"

if [ -n "$ARTIFACT_HASH" -o -e "$ARTIFACT_HASH_FILENAME" ]; then
    ARTIFACT_HASH="${ARTIFACT_HASH-"$( cat "$ARTIFACT_HASH_FILENAME" )"}"
    REPO_URL="http://freeipa-org-pr-ci.s3-website.eu-central-1.amazonaws.com/jobs/${ARTIFACT_HASH}/rpms/freeipa-prci.repo"
    SYSTEM=$(print-build-system "$ARTIFACT_HASH")
elif [ -n "$COPR_REPO" ]; then
    REPO_URL="$COPR_REPO"

    # Derive SYSTEM from repo URL.
    #
    # This matches the path scheme for copr.fedorainfracloud.org, but may
    # not be correct for copr.devel.redhat.com or other COPR instances.
    SYSTEM=$(basename $(dirname "$REPO_URL"))
else
    die "Must create $ARTIFACT_HASH_FILENAME, or specify ARTIFACT_HASH or COPR_REPO"
fi

# Download repo file.  Later we will patch the Dockerfile to
# copy it into the container.
REPO_FILE=devel/freeipa.repo
curl -s -o "$REPO_FILE" "$REPO_URL" \
    || die "Error downloading repo file from '$REPO_URL'"

item="Dockerfile.$SYSTEM"
[ -e "$item" ] || die "'$item' does not exist"
successed_files=()
failured_files=()

case "$SYSTEM" in
    "fedora-rawhide" \
    | "fedora-32" \
    | "fedora-31" \
    | "fedora-30" \
    | "fedora-23" \
    | "centos-7" \
    | "centos-8" )
        yield "INFO:Checking ${item}"
        ;;
    * )
        die "No supported ${item}"
        ;;
esac
cp -f "${item}" "Dockerfile.prci"
patch-dockerfile Dockerfile.prci "$REPO_FILE"
set -o pipefail
if docker run --security-opt seccomp=unconfined \
                --rm -it \
                --volume "$PWD:/data:z" \
                --workdir "/data" \
                quay.io/buildah/stable \
                buildah --storage-driver vfs bud --isolation chroot -f Dockerfile.prci .
then
    yield "INFO:$( basename "${item}" ) build properly"
    successed_files+=( "$( basename "${item}" )")
else
    yield "ERROR:$( basename "${item}" ) failed to build"
    failured_files+=( "$( basename "${item}" )")
fi
rm -f Dockerfile.prci
