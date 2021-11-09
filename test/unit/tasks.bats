#!/usr/bin/env bats

# https://opensource.com/article/19/2/testing-bash-bats

load '../libs/bats-support/load'
load '../libs/bats-assert/load'


@test "tasks_helper_check_level" {
    source './init/tasks.inc.sh'

    run tasks_helper_check_level "DEBUG"
    assert_success
    run tasks_helper_check_level "INFO"
    assert_success
    run tasks_helper_check_level "WARNING"
    assert_success
    run tasks_helper_check_level "ERROR"
    assert_success

    run tasks_helper_check_level "ANYTHING"
    assert_failure
}


@test "tasks_helper_msg" {
    source './init/tasks.inc.sh'

    run tasks_helper_msg "DEBUG" "test" 1>/dev/null
    assert_output "DEBUG:test"

    run tasks_helper_msg "INFO" "test" 1>/dev/null
    assert_output "INFO:test"

    run tasks_helper_msg "WARNING" "test" 1>/dev/null
    assert_output "WARNING:test"

    run tasks_helper_msg "ERROR" "test" 1>/dev/null
    assert_output "ERROR:test"
}


@test "tasks_helper_msg_debug" {
    source './init/tasks.inc.sh'

    run tasks_helper_msg_debug "test" 1>/dev/null
    assert_output "DEBUG:test"
}

@test "tasks_helper_msg_info" {
    source './init/tasks.inc.sh'

    run tasks_helper_msg_info "test" 1>/dev/null
    assert_output "INFO:test"
}

@test "tasks_helper_msg_warning" {
    source './init/tasks.inc.sh'

    run tasks_helper_msg_warning "test" 1>/dev/null
    assert_output "WARNING:test"
}

@test "tasks_helper_msg_error" {
    source './init/tasks.inc.sh'

    run tasks_helper_msg_error "test" 1>/dev/null
    assert_output "ERROR:test"
}



@test "tasks_helper_error" {
    source './init/tasks.inc.sh'

    function func_failure {
        local retcode=$1
        shift 1
        [ "$retcode" == "" ] && retcode=127
        [ $retcode -eq 0 ] && retcode=127
        return $retcode
    }
    export -f func_failure

    run tasks_helper_error "test"
    assert_failure
    assert_output <<EOF
ERROR:errcode=1; traceback:
ERROR:test
EOF
}


@test "tasks_helper_are_step_functions" {
    source './init/tasks.inc.sh'

    run tasks_helper_are_step_functions
    assert_success

    run tasks_helper_are_step_functions ""
    assert_failure

    function module_step_anything {
        :
    }
    export -f module_step_anything
    run tasks_helper_are_step_functions "module_step_anything"
    assert_success

    run tasks_helper_are_step_functions "module_step_anything_not_function"
    assert_failure
    function step_anything {
        :
    }
    export -f step_anything
    run tasks_helper_are_step_functions "step_anything"
    assert_failure

    function module_nostep_anything {
        :
    }
    export -f module_nostep_anything
    run tasks_helper_are_step_functions "module_nostep_anything"
    assert_failure

    function module_helper_anything {
        :
    }
    export -f module_helper_anything
    run tasks_helper_are_step_functions "module_helper_anything"
    assert_failure
}


@test "tasks_helper_add_tasks" {
    source './init/tasks.inc.sh'

    function module_nostep_anything {
        :
    }
    export -f module_nostep_anything
    run tasks_helper_add_tasks "module_nostep_anything"
    assert_failure

    function module_step_anything {
        :
    }
    export -f module_step_anything
    function add_tasks_and_list
    {
        tasks_helper_add_tasks "$@"
        tasks_helper_list
    }
    export -f add_tasks_and_list
    run add_tasks_and_list "module_step_anything"
    assert_success
    assert_output "module_step_anything"
    run add_tasks_and_list "module_step_anything" "module_step_anything"
    assert_success
    assert_output "module_step_anything, module_step_anything"
}


@test "tasks_helper_clean" {
    source './init/tasks.inc.sh'

    function module_step_anything {
        :
    }
    export -f module_step_anything

    function add_tasks_clean_and_list
    {
        tasks_helper_add_tasks "$@" \
        && tasks_helper_clean \
        && tasks_helper_list
    }
    export -f add_tasks_clean_and_list

    function clean_tasks_and_list
    {
        tasks_helper_clean \
        && tasks_helper_list
    }
    export -f clean_tasks_and_list

    run clean_tasks_and_list
    assert_success
    assert_output ""

    run add_tasks_clean_and_list "module_step_anything"
    assert_success
    assert_output ""

    run add_tasks_clean_and_list "module_step_anything" "module_step_anything"
    assert_success
    assert_output ""
}


@test "tasks_helper_has_step_task" {
    source './init/tasks.inc.sh'

    function module_step_anything_1 {
        :
    }
    export -f module_step_anything_1

    function module_step_anything_2 {
        :
    }
    export -f module_step_anything_2

    function module_step_anything_3 {
        :
    }
    export -f module_step_anything_3

    function add_tasks_list_and_check
    {
        func_to_check="$1"
        shift 1
        tasks_helper_add_tasks "$@" \
        && tasks_helper_list \
        && tasks_helper_has_step_task "${func_to_check}"
    }
    export -f add_tasks_list_and_check


    run add_tasks_list_and_check "module_step_anything_3" "module_step_anything_3"
    assert_output "module_step_anything_3"
    assert_success

    run add_tasks_list_and_check "module_step_anything_3" "module_step_anything_1" "module_step_anything_3"
    assert_output "module_step_anything_1, module_step_anything_3"
    assert_success

    run add_tasks_list_and_check "module_step_anything_3" "module_step_anything_3" "module_step_anything_1"
    assert_output "module_step_anything_3, module_step_anything_1"
    assert_success


    run add_tasks_list_and_check "module_step_anything_2" "module_step_anything_3"
    assert_output "module_step_anything_3"
    assert_failure

    run add_tasks_list_and_check "module_step_anything_2" "module_step_anything_1" "module_step_anything_3"
    assert_output "module_step_anything_1, module_step_anything_3"
    assert_failure

    run add_tasks_list_and_check "module_step_anything_2" "module_step_anything_3" "module_step_anything_1"
    assert_output "module_step_anything_3, module_step_anything_1"
    assert_failure
}


@test "tasks_helper_remove_task" {
    source './init/tasks.inc.sh'

    function module_wrongstep_anything {
        :
    }
    export -f module_wrongstep_anything

    function module_step_anything_1 {
        :
    }
    export -f module_step_anything_1

    function module_step_anything_2 {
        :
    }
    export -f module_step_anything_2

    function module_step_anything_3 {
        :
    }
    export -f module_step_anything_3

    function add_tasks_remove_list_and_check
    {
        local func_to_remove="$1"
        shift 1
        tasks_helper_add_tasks "$@" \
        && tasks_helper_remove_task "${func_to_remove}" \
        && tasks_helper_list \
        && ! tasks_helper_has_step_task "${func_to_remove}"
    }
    export -f add_tasks_remove_list_and_check

    run add_tasks_remove_list_and_check "module_step_anything_1"
    assert_output ""
    assert_success

    run add_tasks_remove_list_and_check "module_wrongstep_anything"
    assert_failure

    run add_tasks_remove_list_and_check "module_step_anything_1" "module_step_anything_1"
    assert_output ""
    assert_success

    run add_tasks_remove_list_and_check "module_step_anything_1" "module_step_anything_1" "module_step_anything_2" "module_step_anything_3"
    assert_output "module_step_anything_2, module_step_anything_3"
    assert_success

    run add_tasks_remove_list_and_check "module_step_anything_1" "module_step_anything_2" "module_step_anything_1" "module_step_anything_3"
    assert_output "module_step_anything_2, module_step_anything_3"
    assert_success

    run add_tasks_remove_list_and_check "module_step_anything_1" "module_step_anything_2" "module_step_anything_3" "module_step_anything_1"
    assert_output "module_step_anything_2, module_step_anything_3"
    assert_success

    # Remove all the repeated tasks
    run add_tasks_remove_list_and_check "module_step_anything_1" "module_step_anything_1" "module_step_anything_1" "module_step_anything_2" "module_step_anything_3"
    assert_output "module_step_anything_2, module_step_anything_3"
    assert_success

    run add_tasks_remove_list_and_check "module_step_anything_1" "module_step_anything_2" "module_step_anything_1" "module_step_anything_1" "module_step_anything_3"
    assert_output "module_step_anything_2, module_step_anything_3"
    assert_success

    run add_tasks_remove_list_and_check "module_step_anything_1" "module_step_anything_2" "module_step_anything_3" "module_step_anything_1" "module_step_anything_1"
    assert_output "module_step_anything_2, module_step_anything_3"
    assert_success

    run add_tasks_remove_list_and_check "module_step_anything_1" "module_step_anything_1" "module_step_anything_2" "module_step_anything_1" "module_step_anything_3"
    assert_output "module_step_anything_2, module_step_anything_3"
    assert_success

    run add_tasks_remove_list_and_check "module_step_anything_1" "module_step_anything_2" "module_step_anything_1" "module_step_anything_3" "module_step_anything_1"
    assert_output "module_step_anything_2, module_step_anything_3"
    assert_success
}


@test "tasks_helper_remove_task_list" {
    source './init/tasks.inc.sh'

    function module_wrongstep_anything {
        :
    }
    export -f module_wrongstep_anything

    function module_step_anything_1 {
        :
    }
    export -f module_step_anything_1

    function module_step_anything_2 {
        :
    }
    export -f module_step_anything_2

    function module_step_anything_3 {
        :
    }
    export -f module_step_anything_3

    function module_step_anything_4 {
        :
    }
    export -f module_step_anything_4

    function module_step_anything_5 {
        :
    }
    export -f module_step_anything_5

    function add_tasks_remove_list_and_check
    {
        local scenario_to_prepare="$1"
        shift 1
        helper_prepare_tasks "${scenario_to_prepare}" \
        && tasks_helper_remove_task_list "$@" \
        && tasks_helper_list \
        && {
            for func_to_remove in "$@"; do
                ! tasks_helper_has_step_task "${func_to_remove}" || return 1
            done
        }
    }
    export -f add_tasks_remove_list_and_check

    function helper_prepare_tasks
    {
        local list_tasks=()
        case "$1" in
            "scenario-0" )
                return 0
                ;;
            "scenario-1" )
                list_tasks+=("module_step_anything_1")
                ;;
            "scenario-2" )
                list_tasks+=("module_step_anything_1")
                list_tasks+=("module_step_anything_1")
                ;;
            "scenario-3" )
                list_tasks+=("module_step_anything_1")
                list_tasks+=("module_step_anything_2")
                list_tasks+=("module_step_anything_3")
                ;;
            * )
                return 1
                ;;
        esac
        tasks_helper_add_tasks "${list_tasks[@]}"
        return 0
    }
    export -f helper_prepare_tasks


    run add_tasks_remove_list_and_check "scenario-0" "module_wrongstep_anything"
    assert_failure

    run add_tasks_remove_list_and_check "scenario-1" "module_wrongstep_anything"
    assert_failure


    run add_tasks_remove_list_and_check "scenario-0" "module_step_anything_5"
    assert_output ""
    assert_success

    run add_tasks_remove_list_and_check "scenario-1" "module_step_anything_5"
    assert_output "module_step_anything_1"
    assert_success

    run add_tasks_remove_list_and_check "scenario-1" "module_step_anything_1"
    assert_output ""
    assert_success

    run add_tasks_remove_list_and_check "scenario-2" "module_step_anything_1"
    assert_output ""
    assert_success

    run add_tasks_remove_list_and_check "scenario-3" "module_step_anything_1" "module_step_anything_3"
    assert_output "module_step_anything_2"
    assert_success
}


@test "tasks_helper_shift_args" {
    source './init/tasks.inc.sh'

    export ARGS

    function helper_list_args
    {
        local first=1
        for item in "${ARGS[@]}"; do
            if [ $first -eq 1 ]; then
                echo -n "$item"
                first=0
            else
                echo -n ", $item"
            fi
        done
    }
    export -f helper_list_args

    function helper_set_args_and_shift
    {
        ARGS=("$@")
        tasks_helper_shift_args \
        && helper_list_args
    }
    export -f helper_set_args_and_shift

    run helper_set_args_and_shift
    assert_success
    assert_output ""

    run helper_set_args_and_shift "arg1"
    assert_success
    assert_output ""

    run helper_set_args_and_shift "arg1" "arg2" "arg3"
    assert_success
    assert_output "arg2, arg3"
}


@test "tasks_helper_list" {
    source './init/tasks.inc.sh'

    function module_step_anything_1 {
        :
    }
    export -f module_step_anything_1

    function module_step_anything_2 {
        :
    }
    export -f module_step_anything_2

    function module_step_anything_3 {
        :
    }
    export -f module_step_anything_3

    function add_tasks_and_list
    {
        tasks_helper_add_tasks "$@" \
        && tasks_helper_list
    }
    export -f add_tasks_and_list

    run add_tasks_and_list
    assert_output ""
    assert_success

    run add_tasks_and_list "module_step_anything_1"
    assert_output "module_step_anything_1"
    assert_success

    run add_tasks_and_list "module_step_anything_1" "module_step_anything_2"
    assert_output "module_step_anything_1, module_step_anything_2"
    assert_success

    run add_tasks_and_list "module_step_anything_1" "module_step_anything_2" "module_step_anything_3"
    assert_output "module_step_anything_1, module_step_anything_2, module_step_anything_3"
    assert_success
}


@test "tasks_helper_update_step" {
    source './init/tasks.inc.sh'

    function module_wrongstep_anything {
        :
    }
    export -f module_wrongstep_anything

    function module_step_anything_1 {
        :
    }
    export -f module_step_anything_1

    function module_step_anything_2 {
        :
    }
    export -f module_step_anything_2

    function module_step_anything_3 {
        :
    }
    export -f module_step_anything_3

    function add_tasks_and_list
    {
        tasks_helper_add_tasks "$@" \
        && tasks_helper_list
    }
    export -f add_tasks_and_list

    run add_tasks_and_list
    assert_output ""
    assert_success
}

@test "tasks_helper_add_after" {
    source './init/tasks.inc.sh'

    function module_wrongstep_anything {
        :
    }
    export -f module_wrongstep_anything

    function module_step_anything_1 {
        :
    }
    export -f module_step_anything_1

    function module_step_anything_2 {
        :
    }
    export -f module_step_anything_2

    function module_step_anything_3 {
        :
    }
    export -f module_step_anything_3

    function add_tasks_after_and_list
    {
        local task_to_match="$1"
        shift 1
        local my_task_list=()

        my_task_list+=("module_step_anything_1")
        my_task_list+=("module_step_anything_2")
        my_task_list+=("module_step_anything_3")

        tasks_helper_clean \
        && tasks_helper_add_tasks "${my_task_list[@]}" \
        && tasks_helper_add_after "${task_to_match}" "$@" \
        && tasks_helper_list
    }
    export -f add_tasks_after_and_list

    function empty_add_tasks_after_and_list
    {
        local task_to_match="$1"
        shift 1
        tasks_helper_clean \
        && tasks_helper_add_after "${task_to_match}" "$@" \
        && tasks_helper_list
    }
    export -f empty_add_tasks_after_and_list

    run add_tasks_after_and_list "module_wrongstep_anything"
    assert_failure
    assert_output --partial "ERROR:errcode=1; traceback:"
    assert_output --partial "ERROR:'module_wrongstep_anything' is not a step function"

    run add_tasks_after_and_list "module_step_anything_1" "module_wrongstep_anything"
    assert_failure
    assert_output --partial "ERROR:errcode=1; traceback:"
    assert_output --partial "ERROR:Some tasks_to_add has some no step function: module_wrongstep_anything"

    run empty_add_tasks_after_and_list "module_step_anything_1" "module_step_anything_2" "module_step_anything_3"
    assert_success
    assert_output ""

    run add_tasks_after_and_list "module_step_anything_1" "module_step_anything_2" "module_step_anything_3"
    assert_success
    assert_output "module_step_anything_1, module_step_anything_2, module_step_anything_3, module_step_anything_2, module_step_anything_3"

    run add_tasks_after_and_list "module_step_anything_2" "module_step_anything_2" "module_step_anything_3"
    assert_success
    assert_output "module_step_anything_1, module_step_anything_2, module_step_anything_2, module_step_anything_3, module_step_anything_3"

    run add_tasks_after_and_list "module_step_anything_3" "module_step_anything_2" "module_step_anything_3"
    assert_success
    assert_output "module_step_anything_1, module_step_anything_2, module_step_anything_3, module_step_anything_2, module_step_anything_3"
}

@test "tasks_helper_add_before" {
    source './init/tasks.inc.sh'

    function module_wrongstep_anything {
        :
    }
    export -f module_wrongstep_anything

    function module_step_anything_1 {
        :
    }
    export -f module_step_anything_1

    function module_step_anything_2 {
        :
    }
    export -f module_step_anything_2

    function module_step_anything_3 {
        :
    }
    export -f module_step_anything_3

    function add_tasks_before_and_list
    {
        local task_to_match="$1"
        shift 1
        local my_task_list=()

        my_task_list+=("module_step_anything_1")
        my_task_list+=("module_step_anything_2")
        my_task_list+=("module_step_anything_3")

        tasks_helper_clean \
        && tasks_helper_add_tasks "${my_task_list[@]}" \
        && tasks_helper_add_before "${task_to_match}" "$@" \
        && tasks_helper_list
    }
    export -f add_tasks_before_and_list

    function empty_add_tasks_before_and_list
    {
        local task_to_match="$1"
        shift 1
        tasks_helper_clean \
        && tasks_helper_add_before "${task_to_match}" "$@" \
        && tasks_helper_list
    }
    export -f empty_add_tasks_before_and_list

    run add_tasks_before_and_list "module_wrongstep_anything"
    assert_failure
    assert_output --partial "ERROR:errcode=1; traceback:"
    assert_output --partial "ERROR:'module_wrongstep_anything' is not a step function"

    run add_tasks_before_and_list "module_step_anything_1" "module_wrongstep_anything"
    assert_failure
    assert_output --partial "ERROR:errcode=1; traceback:"
    assert_output --partial "ERROR:Some tasks_to_add has some no step function: module_wrongstep_anything"

    run empty_add_tasks_before_and_list "module_step_anything_1" "module_step_anything_2" "module_step_anything_3"
    assert_success
    assert_output ""

    run add_tasks_before_and_list "module_step_anything_1" "module_step_anything_2" "module_step_anything_3"
    assert_success
    assert_output "module_step_anything_2, module_step_anything_3, module_step_anything_1, module_step_anything_2, module_step_anything_3"

    run add_tasks_before_and_list "module_step_anything_2" "module_step_anything_2" "module_step_anything_3"
    assert_success
    assert_output "module_step_anything_1, module_step_anything_2, module_step_anything_3, module_step_anything_2, module_step_anything_3"

    run add_tasks_before_and_list "module_step_anything_3" "module_step_anything_2" "module_step_anything_3"
    assert_success
    assert_output "module_step_anything_1, module_step_anything_2, module_step_anything_2, module_step_anything_3, module_step_anything_3"
}

@test "tasks_helper_execute" {
    source './init/tasks.inc.sh'

    function module_step_anything_1 {
        echo "${FUNCNAME[0]}"
    }
    export -f module_step_anything_1

    function module_step_anything_2 {
        echo "${FUNCNAME[0]}"
    }
    export -f module_step_anything_2

    function module_step_anything_3 {
        echo "${FUNCNAME[0]}"
    }
    export -f module_step_anything_3

    function helper_tasks_execute
    {
        tasks_helper_clean
        if [ ${#my_task_list[@]} -gt 0 ]; then
            tasks_helper_add_tasks "${my_task_list[@]}"
        fi
        tasks_helper_list \
        && tasks_helper_execute
    }
    export -f helper_tasks_execute
    export my_task_list

    my_task_list=()
    run helper_tasks_execute
    assert_success
    assert_output ""

    my_task_list=("module_step_anything_1")
    run helper_tasks_execute
    assert_success
    assert_output << EOF
module_step_anything_1
INFO:Running step: 'module_step_anything_1'
module_step_anything_1
EOF

    my_task_list=("module_step_anything_1" "module_step_anything_2" "module_step_anything_2" "module_step_anything_3")
    run helper_tasks_execute
    assert_success
    assert_output << EOF
module_step_anything_1, module_step_anything_2, module_step_anything_2, module_step_anything_3
INFO:Running step: 'module_step_anything_1'
module_step_anything_1
INFO:Running step: 'module_step_anything_2'
module_step_anything_2
INFO:Running step: 'module_step_anything_2'
module_step_anything_2
INFO:Running step: 'module_step_anything_3'
module_step_anything_3
EOF
}

