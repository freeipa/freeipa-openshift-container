#!/usr/bin/env bats

# https://opensource.com/article/19/2/testing-bash-bats

load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../libs/bats-mock/load'


if command -v podman &> /dev/null; then
    export DOCKER=podman
elif command -v docker &> /dev/null; then
    export DOCKER=docker
else
    export DOCKER=
fi


NAMESPACE="test-$( git rev-parse --short HEAD )"


function exit-with-message
{
    local _ret="$1"
    shift 1
    [ "${_ret}" != "" ] || _ret=127
    [ "${_ret}" -ne 0 ] || _ret=127
    printf "ERROR:%s\n" "$*" >&2
    exit ${_ret}
}
export -f exit-with-message


function setup
{
    [ "${KUBECONFIG}" != "" ] || {
        exit-with-message 1 "ERROR:KUBECONFIG is not defined"
    }
    ! oc get "namespace/${NAMESPACE}" || oc delete "namespace/${NAMESPACE}"
    oc new-project "${NAMESPACE}"
    kustomize build deploy/admin | oc create -f -
}


function teardown
{
    kustomize build deploy/admin | oc delete -f - \
    && oc delete "project/${NAMESPACE}" --grace-period=0 \
    && oc wait --for=delete "namespace/${NAMESPACE}"
}


@test "template-create" {
    function check-make-template-create {
        ! oc get templates/freeipa &>/dev/null || make template-delete &>/dev/null
        make template-create \
        && oc get templates/freeipa \
        && ! make template-create
    }
    export -f check-make-template-create

    run check-make-template-create
    assert_success
}


@test "template-delete" {
    function check-make-template-delete {
        oc get template/freeipa &>/dev/null || make template-create &>/dev/null
        make template-delete \
        && oc wait --for=delete "template/freeipa" --timeout=30s \
        && ! make template-delete
    }
    export -f check-make-template-delete

    run check-make-template-delete
    assert_success
}


@test "template-new-app-rm-app" {
    function check-make-template-create-new-app {
        ! oc get templates/freeipa &>/dev/null || make template-delete &>/dev/null
        ! make template-new-app || return 100
        make template-rm-app
        make template-create \
        && make template-new-app \
        && oc wait --for=condition=Ready pod/freeipa --timeout=420s \
        && ! make template-new-app
    }
    export -f check-make-template-create-new-app

    function check-make-template-create-rm-app {
        make template-rm-app \
        && oc wait --for=delete pod/freeipa --timeout=30s \
        && ! make template-rm-app
    }
    export -f check-make-template-create-rm-app

    run check-make-template-create-new-app
    assert_success

    run check-make-template-create-rm-app
    assert_success
}

