#!/bin/bash

# Variables
declare -a ARGS
declare -a ARGS_ORIGINAL
declare -a TASKS_LIST

ARGS=("$@")
ARGS_ORIGINAL=("$@")
TASKS_LIST=()

function tasks_add_tasks
{
    TASKS_LIST+=("$@")
}

function tasks_clean
{
    TASKS_LIST=()
}

function tasks_has_task
{
    for item in "${TASKS_LIST[@]}"; do
        [ "${item}" == "${task}" ] && return 0
    done
    return 1
}

function tasks_del_task
{
    local task="$1"
    local list=()

    for item in "${TASKS_LIST[@]}"; do
        [ "${item}" == "${task}" ] && continue
        list+=("${item}")
    done
    TASKS_LIST=("${list[@]}")
}

function taks_del_tasks
{
    for item in "$@"; do
        tasks_del_task "${item}"
    done
}

function tasks_shift_args
{
    [ ${#ARGS[@]} -eq 0 ] && return 0
    unset ARGS[0]
}

function tasks_list
{
    for task in "${TASKS_LIST[@]}"; do
        echo "${task}"
    done
}

function tasks_execute
{
    tasks_list
    for task in "${TASKS_LIST[@]}"; do
        echo "INFO:Running '${task}'" >&2
        "${task}" || {
            echo "ERROR:Executing '${task}'"
            exit 1
        }
    done
    return 0
}

function tasks_exchange
{
    local list=()
    local task_to_match="$1"
    local task_to_set="$2"
    for task in "${TASKS_LIST[@]}"; do
        if [ "${task_to_match}" == "${task}" ]; then
            list+=("${task_to_set}")
        else
            list+=("${task}")
        fi
    done
    TASKS_LIST=("${list[@]}")
}

function tasks_add_after
{
    local list=()
    local task_to_match="$1"
    local task_to_add="$2"
    for task in "${TASKS_LIST[@]}"; do
        if [ "${task_to_match}" == "${task}" ]; then
            list+=("${task}")
            list+=("${task_to_add}")
        else
            list+=("${task}")
        fi
    done
    TASKS_LIST=("${list[@]}")
}
