#!/bin/bash

##
# Build the container using RPMs from a specified repository.
# Supported repository sources are PR-CI and COPR.
#
# Usage:
#
#   ARTIFACT_HASH="c8dbfc76-c4eb-11ea-88a6-fa163e90bd6d" ./devel/build-from-repo.sh
#
#   or
#
#   COPR_REPO=https://.../user-project-fedora-32.repo ./devel/build-from-repo.sh
##

ARTIFACT_HASH_FILENAME="artifact-hash.txt"
LATEST_FEDORA="fedora-33"
DOCKERFILE="$( mktemp Dockerfile.XXXX )"
QUAY_EXPIRATION="${QUAY_EXPIRATION:-never}"
IMAGE_TAG_BASE="${IMAGE_TAG_BASE:-local/freeipa-server:}"
IMAGE_BUILDER="${IMAGE_BUILDER:-docker}"

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
        "centos-8" \
        | "fedora-31" \
        | "fedora-32" \
        | "fedora-33" \
        | "fedora-rawhide" )
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
        # After the initial dnf commands that upgrade packages and
        # install FreeIPA, inject the repo file and upgrade packages.
        #
        # Unfortunately we cannot restrict the operation to only the
        # devel repo, because the devel packages could introduce new
        # dependencies.  So although we just did a 'dnf clean all',
        # we now have to download all the repo metadata again.  I
        # don't see a good workaround that keeps the initial package
        # upgrade/install as a standalone step (important for
        # caching) while also keeping the layer size small).
        #
        # avoid (re)downloading other repo content that was already
        # cleaned.
        if [[ "${line}" =~ "dnf clean all" ]]
        then
            {
                printf "%s\n" "${line}"
                printf "ARG quay_expiration=never\n"
                printf "LABEL quay.expires-after=\${quay_expiration}\n"
                printf "COPY \"%s\" \"%s\"\n" "${repofilepath}" "/etc/yum.repos.d/freeipa-development.repo"
                printf "RUN dnf upgrade -y && dnf clean all\n"
            } >> "${dockerfilepath}"
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

if [ -n "${ARTIFACT_HASH}" ] || [ -e "${ARTIFACT_HASH_FILENAME}" ]; then
    ARTIFACT_HASH="${ARTIFACT_HASH-"$( cat "${ARTIFACT_HASH_FILENAME}" )"}"
    REPO_URL="http://freeipa-org-pr-ci.s3-website.eu-central-1.amazonaws.com/jobs/${ARTIFACT_HASH}/rpms/freeipa-prci.repo"
    SYSTEM="$( print-build-system "${ARTIFACT_HASH}" )"
elif [ -n "${COPR_REPO}" ]; then
    REPO_URL="${COPR_REPO}"

    # Derive SYSTEM from repo URL.
    #
    # This matches the path scheme for copr.fedorainfracloud.org, but may
    # not be correct for copr.devel.redhat.com or other COPR instances.
    SYSTEM="$( basename "$( dirname "${REPO_URL}" )" )"
else
    die "Must create ${ARTIFACT_HASH_FILENAME}, or specify ARTIFACT_HASH or COPR_REPO"
fi

# Download repo file.  Later we will patch the Dockerfile to
# copy it into the container.
#
# Because the build cache is mtime aware, to avoid spurious cache
# invalidation we download the file elsewhere.  We only overwrite
# the existing file if:
#
# - it doesn't exist yet
# - the repo files differ
# - explicitly told to replace it, via $FORCE env var
#
REPO_FILE=devel/freeipa.repo
curl -s -o "${REPO_FILE}".tmp "${REPO_URL}" \
    || die "Error downloading repo file from '${REPO_URL}'"
if [ -n "${FORCE}" ] || [ ! -e "${REPO_FILE}" ] || ! diff -q "${REPO_FILE}".tmp "${REPO_FILE}"; then
    mv "${REPO_FILE}".tmp "${REPO_FILE}"
else
    rm "${REPO_FILE}".tmp
fi

item="Dockerfile.${SYSTEM}"
[ -e "${item}" ] || die "'${item}' does not exist"
successed_files=()
failured_files=()

case "${SYSTEM}" in
    "fedora-rawhide" \
    | "fedora-33" \
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
cp -f "${item}" "${DOCKERFILE}"
patch-dockerfile "${DOCKERFILE}" "${REPO_FILE}"
set -o pipefail
IMAGE_TAG="${IMAGE_TAG_BASE}${SYSTEM}"
case "${IMAGE_BUILDER}" in
    docker )
        docker build -t "${IMAGE_TAG}" \
                     --build-arg "quay_expiration=${QUAY_EXPIRATION}" \
                     -f "${DOCKERFILE}" .
        ;;
    podman )
        podman build -t "${IMAGE_TAG}" \
                     --build-arg "quay_expiration=${QUAY_EXPIRATION}" \
                     -f "${DOCKERFILE}" .
        ;;
    kaniko )
        /kaniko/executor --destination="${IMAGE_TAG}" \
                         --build-arg "quay_expiration=${QUAY_EXPIRATION}" \
                         --dockerfile="${DOCKERFILE}" \
                         --context "${PWD}"
        ;;
    buildah )
        buildah bud -t "${IMAGE_TAG}" \
                    --build-arg "quay_expiration=${QUAY_EXPIRATION}" \
                    --layers \
                    --isolation chroot \
                    -f "${DOCKERFILE}" .
        ;;
    * )
        die "${IMAGE_BUILDER} not supported"
        ;;
esac
STATUS=$?

rm -f "${DOCKERFILE}"

if [ "$STATUS" -eq 0 ]
then
    yield "INFO:$( basename "${item}" ) build properly"
    yield "INFO:Now you can use the '${IMAGE_TAG}' image"
    successed_files+=( "$( basename "${item}" )")
    exit 0
else
    yield "ERROR:$( basename "${item}" ) failed to build"
    failured_files+=( "$( basename "${item}" )")
    exit 1
fi
