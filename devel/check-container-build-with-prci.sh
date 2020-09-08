#!/bin/bash

##
# It requires the hash to access the RPMS to be stored in the artifact-hash.txt file,
# or pass on the value as environment variable.
#
# Usage:
#   ARTIFACT_HASH="c8dbfc76-c4eb-11ea-88a6-fa163e90bd6d" ./devel/check-container-build-with-prci.sh
##

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


function download-repo-file-to
{
    local output
    local repo_url
    output="$1"

    [ "$output" == "" ] && die "'${output}' destination file can not be empty"
    repo_url="http://freeipa-org-pr-ci.s3-website.eu-central-1.amazonaws.com/jobs/${ARTIFACT_HASH}/rpms/freeipa-prci.repo"
    curl -s -o "${output}" "${repo_url}" \
    || die "Error downloading repo file from '${repo_url}'"
} # download-repo-file-to


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
            printf "COPY \"%s\" \"%s\"\n" "${repofilepath}" "/etc/yum.repos.d/freeipa-development.repo" >> "${dockerfilepath}"
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
[ "${ARTIFACT_HASH}" == "" ] && [ ! -e "artifact-hash.txt" ] && die "No AERTIFACT_HASH variable nor artifact-hash.txt file was specified"
ARTIFACT_HASH="${ARTIFACT_HASH-"$( cat artifact-hash.txt )"}"

ARTIFACT_HASH="${ARTIFACT_HASH}" download-repo-file-to devel/freeipa-prci.repo

item="Dockerfile.$( print-build-system "${ARTIFACT_HASH}" )"
[ -e "$item" ] || die "'$item' does not exist"
successed_files=()
failured_files=()

system="${item##*.}"
case "${system}" in
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
patch-dockerfile Dockerfile.prci devel/freeipa-prci.repo
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
