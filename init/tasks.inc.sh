#!/bin/bash

# Variables
declare -a ARGS
declare -a ARGS_ORIGINAL
declare -a TASKS_LIST

ARGS=("$@")
# shellcheck disable=SC2034
ARGS_ORIGINAL=("$@")
TASKS_LIST=()

function tasks_helper_check_level
{
    local msg_level="$1"
    shift 1
    case "${msg_level}" in
        "DEBUG" | "INFO" | "WARNING" | "ERROR" )
            return 0
            ;;
        * )
            return 1
            ;;
    esac
}

function tasks_helper_msg
{
    local msg_level="$1"
    shift 1
    tasks_helper_check_level "${msg_level}" || return 1
    echo "${msg_level}:$*" >&2
}

function tasks_helper_msg_debug
{
    tasks_helper_msg "DEBUG" "$*"
}

function tasks_helper_msg_info
{
    tasks_helper_msg "INFO" "$*"
}

function tasks_helper_msg_warning
{
    tasks_helper_msg "WARNING" "$*"
}

function tasks_helper_msg_error
{
    tasks_helper_msg "ERROR" "$*"
}

function tasks_helper_error
{
    local errcode=$?
    [ ${errcode} -ne 0 ] || errcode=127
    tasks_helper_msg_error "errcode=${errcode}; traceback:${FUNCTION[*]}"
    tasks_helper_msg_error "$*"
    exit $errcode
}

function tasks_helper_are_step_functions
{
    local item
    local item_type
    [ "$#" -gt 0 ] || return 0
    for item in "$@"; do
        [ "${item}" != "" ] || return 1
        item_type=$(type -t "${item}")
        [ "${item_type}" == "function" ] || return 1
        [ "$item" == "${item#*_}" ] && return 1
        item="${item#*_}"
        [ "$item" == "${item%%_*}" ] && return 1
        item="${item%%_*}"
        [ "$item" != "step" ] && return 1
    done
    return 0
}

function tasks_helper_add_tasks
{
    tasks_helper_are_step_functions "$@" || tasks_helper_error "Some of this tasks are not a step function: $*"
    TASKS_LIST+=("$@")
}

function tasks_helper_clean
{
    TASKS_LIST=()
}

function tasks_helper_has_step_task
{
    local task="$1"
    shift 1
    tasks_helper_are_step_functions "$@" || tasks_helper_error "Some of this tasks are not a step function: $*"
    for item in "${TASKS_LIST[@]}"; do
        if [ "${item}" == "${task}" ]; then
            return 0
        fi
    done
    return 1
}

function tasks_helper_remove_task
{
    local task="$1"
    local list=()

    tasks_helper_are_step_functions "$1" || tasks_helper_error "The task to remove is not a step function: $1"

    for item in "${TASKS_LIST[@]}"; do
        [ "${item}" != "${task}" ] || continue
        list+=("${item}")
    done
    TASKS_LIST=("${list[@]}")
}

function tasks_helper_remove_task_list
{
    for item in "$@"; do
        tasks_helper_remove_task "${item}"
    done
}

function tasks_helper_shift_args
{
    [ ${#ARGS[@]} -ne 0 ] || return 0
    ARGS=("${ARGS[@]:1}")
}

function tasks_helper_list
{
    local first=1
    for task in "${TASKS_LIST[@]}"; do
        [ ${first} -ne 1 ] || {
            echo -n "${task}"
            first=0
            continue
        }
        echo -n ", ${task}"
    done
    echo ""
}

function tasks_helper_update_step
{
    local list=()
    local task_to_match="$1"
    local task_to_set="$2"
    shift 2

    tasks_helper_are_step_functions "${task_to_match}" || tasks_helper_error "'${task_to_match}' function to match is not a step function"
    tasks_helper_are_step_functions "${task_to_set}" || tasks_helper_error "'${task_to_set}' function to update is not a step function"

    for task in "${TASKS_LIST[@]}"; do
        if [ "${task_to_match}" == "${task}" ]; then
            list+=("${task_to_set}")
        else
            list+=("${task}")
        fi
    done

    TASKS_LIST=("${list[@]}")
}

function tasks_helper_add_after
{
    local list=()
    local task_to_match="$1"
    shift 1
    local tasks_to_add=("$@")

    tasks_helper_are_step_functions "${task_to_match}" || tasks_helper_error "'${task_to_match}' is not a step function"
    tasks_helper_are_step_functions "${tasks_to_add[@]}" || tasks_helper_error "Some tasks_to_add has some no step function:" "${tasks_to_add[@]}"

    for task in "${TASKS_LIST[@]}"; do
        list+=("${task}")
        if [ "${task_to_match}" == "${task}" ]; then
            list+=("${tasks_to_add[@]}")
        fi
    done

    TASKS_LIST=("${list[@]}")
}

function tasks_helper_add_before
{
    local list=()
    local task_to_match="$1"
    shift 1
    local tasks_to_add=("$@")

    tasks_helper_are_step_functions "${task_to_match}" || tasks_helper_error "'${task_to_match}' is not a step function"
    tasks_helper_are_step_functions "${tasks_to_add[@]}" || tasks_helper_error "Some tasks_to_add has some no step function:" "${tasks_to_add[@]}"

    for task in "${TASKS_LIST[@]}"; do
        if [ "${task_to_match}" == "${task}" ]; then
            list+=("${tasks_to_add[@]}")
        fi
        list+=("${task}")
    done

    TASKS_LIST=("${list[@]}")
}

function tasks_helper_execute
{
    for task in "${TASKS_LIST[@]}"; do
        tasks_helper_msg_info "Running step: '${task}'"
        "${task}" || {
            tasks_helper_msg_error "Executing step at: '${task}'"
            exit 1
        }
    done
    return 0
}
