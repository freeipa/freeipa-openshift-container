#!/usr/bin/env bats

# https://opensource.com/article/19/2/testing-bash-bats

load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../libs/bats-mock/load'

@test "container_step_enable_traces" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    function helper_enable_traces {
        container_step_enable_traces
        if [ "${DEBUG_TRACE}" != "" ]; then
            shopt -q -o xtrace || return 1
        fi
        return 0
    }
    export -f helper_enable_traces
    export DEBUG_TRACE

    DEBUG_TRACE=
    run helper_enable_traces
    assert_success

    DEBUG_TRACE=1
    run helper_enable_traces
    assert_success
}


@test "container_step_set_workdir_to_root" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    function helper_container_step_set_workdir_to_root
    {
        local workdir
        container_step_set_workdir_to_root
        workdir="$( pwd 2>/dev/null )"
        [ "${workdir}" == "/" ] || return 1
        return 0
    }
    export helper_container_step_set_workdir_to_root
    run helper_container_step_set_workdir_to_root
    assert_success
    assert_output ""
}


@test "container_step_exec_whitelist_commands" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    function helper_container_step_exec_whitelist_commands
    {
        case "$1" in
            "/bin/install.sh" | \
            "/bin/uninstall.sh" | \
            "/bin/bash" | \
            "bash" )
                ARGS=("bash" "-c" "true")
                ;;
            * )
                ARGS=("bash" "-c" "false")
                ;;
        esac
        container_step_exec_whitelist_commands "${ARGS[@]}"
    }
    export -f helper_container_step_exec_whitelist_commands

    # Success scenarios
    for command in "/bin/install.sh" "/bin/uninstall.sh" "/bin/bash" "bash"; do
        run helper_container_step_exec_whitelist_commands "${command}"
        assert_success
        assert_output ""
    done

    # Just a few failing scenarios
    for command in "sh" "csh" "true" "false"; do
        run helper_container_step_exec_whitelist_commands "${command}"
        assert_failure
        assert_output ""
    done
}


@test "container_step_clean_directories" {
    skip "TODO It needs the container environment"
}


@test "container_step_populate_volume_from_template" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    mock stub container_helper_invoke_populate_volume_from_template
    mock_container_helper_invoke_populate_volume_from_template 0 "/tmp"
    run container_step_populate_volume_from_template
    assert_success
    assert_mock container_helper_invoke_populate_volume_from_template
    mock unstub container_helper_invoke_populate_volume_from_template
}


@test "container_step_workaround_1372562" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    mock stub mkdir
    mock_mkdir 0 -p "/run/lock"
    run container_step_workaround_1372562
    assert_success
    assert_mock mkdir
    mock unstub mkdir
}


@test "container_step_create_directories" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    export DATA=/tmp
    mock stub mkdir
    mock_mkdir 0 -p "/run/ipa" "/run/log" "${DATA}/var/log/journal"
    run container_step_create_directories
    assert_mock mkdir
    assert_success
}


@test "container_step_link_journal" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    export DATA=/tmp
    mock stub ln
    mock_ln 0 -s "${DATA}/var/log/journal" "/run/log/journal"
    run container_step_link_journal
    assert_mock ln
    assert_success
    mock unstub ln
}

@test "container_helper_write_no_poweroff_conf" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    run container_helper_write_no_poweroff_conf "/dev/stdout"
    assert_success
    /bin/cat <<EOF | assert_output
[Service]
FailureAction=none
EOF
}

# TODO Clean-up
# @test "container_helper_write_poweroff_conf" {
#     source './init/tasks.inc.sh'
#     source './init/container.inc.sh'
# 
#     run container_helper_write_poweroff_conf "/dev/stdout"
#     assert_success
#     /bin/cat <<EOF | assert_output
# [Service]
# ExecStartPost=/usr/bin/systemctl poweroff
# EOF
# }


@test "container_helper_link_to_power_off" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    mock stub ln
    mock_ln 0 -s "/usr/lib/systemd/system/ipa-server-configure-first.service.d/service-success-poweroff.conf.template" "/tmp/test"
    run container_helper_link_to_power_off  "/tmp/test"
    assert_success
    assert_mock ln
    mock unstub ln
}


@test "container_step_do_check_terminate_await - args==no-exit" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    export ARGS=("no-exit")
    unset DEBUG_NO_EXIT
    mock stub mkdir container_helper_write_no_poweroff_conf tasks_helper_shift_args utils_is_not_empty_str
    mock_tasks_helper_shift_args 0
    mock_mkdir 0 -p /run/systemd/system/ipa-server-configure-first.service.d
    mock_mkdir 0 -p /run/systemd/system/ipa-server-upgrade.service.d
    mock_container_helper_write_no_poweroff_conf 0 "/run/systemd/system/ipa-server-configure-first.service.d/50-no-poweroff.conf"
    mock_container_helper_write_no_poweroff_conf 0 "/run/systemd/system/ipa-server-upgrade.service.d/50-no-poweroff.conf"
    run container_step_do_check_terminate_await
    assert_success
    assert_mock mkdir container_helper_write_no_poweroff_conf tasks_helper_shift_args utils_is_not_empty_str
    mock unstub mkdir container_helper_write_no_poweroff_conf tasks_helper_shift_args utils_is_not_empty_str
}


@test "container_step_do_check_terminate_await - DEBUG_NO_EXIT" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    export ARGS=()
    export DEBUG_NO_EXIT="1"
    mock stub mkdir container_helper_write_no_poweroff_conf tasks_helper_shift_args utils_is_not_empty_str
    mock_utils_is_not_empty_str 0 "${DEBUG_NO_EXIT}"
    mock_tasks_helper_shift_args 0
    mock_mkdir 0 -p /run/systemd/system/ipa-server-configure-first.service.d
    mock_container_helper_write_no_poweroff_conf 0 "/run/systemd/system/ipa-server-configure-first.service.d/50-no-poweroff.conf"
    mock_mkdir 0 -p /run/systemd/system/ipa-server-upgrade.service.d
    mock_container_helper_write_no_poweroff_conf 0 "/run/systemd/system/ipa-server-upgrade.service.d/50-no-poweroff.conf"
    run container_step_do_check_terminate_await
    assert_success
    assert_mock mkdir container_helper_write_no_poweroff_conf tasks_helper_shift_args utils_is_not_empty_str
    mock unstub mkdir container_helper_write_no_poweroff_conf tasks_helper_shift_args utils_is_not_empty_str
}


@test "container_step_do_check_terminate_await - args[0]==no-exit or DEBUG_NO_EXIT" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    export ARGS=("no-exit")
    export DEBUG_NO_EXIT="1"
    mock stub mkdir container_helper_write_no_poweroff_conf tasks_helper_shift_args utils_is_not_empty_str
    mock_utils_is_not_empty_str 0 "${DEBUG_NO_EXIT}"
    mock_tasks_helper_shift_args 0
    mock_mkdir 0 -p /run/systemd/system/ipa-server-configure-first.service.d
    mock_container_helper_write_no_poweroff_conf 0 "/run/systemd/system/ipa-server-configure-first.service.d/50-no-poweroff.conf"
    mock_mkdir 0 -p /run/systemd/system/ipa-server-upgrade.service.d
    mock_container_helper_write_no_poweroff_conf 0 "/run/systemd/system/ipa-server-upgrade.service.d/50-no-poweroff.conf"
    run container_step_do_check_terminate_await
    assert_success
    assert_mock mkdir container_helper_write_no_poweroff_conf tasks_helper_shift_args utils_is_not_empty_str
    mock unstub mkdir container_helper_write_no_poweroff_conf tasks_helper_shift_args utils_is_not_empty_str
}


@test "container_step_do_check_terminate_await - args[0]==exit-on-finished" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    unset DEBUG_NO_EXIT
    export ARGS=("exit-on-finished")
    mock stub mkdir container_helper_link_to_power_off tasks_helper_shift_args utils_is_not_empty_str
    mock_utils_is_not_empty_str 1 "${DEBUG_NO_EXIT}"
    mock_mkdir 0 -p /run/systemd/system/ipa-server-configure-first.service.d
    mock_container_helper_link_to_power_off 0 "/run/systemd/system/ipa-server-configure-first.service.d/50-success-poweroff.conf"
    mock_mkdir 0 -p /run/systemd/system/ipa-server-upgrade.service.d
    mock_container_helper_link_to_power_off 0 "/run/systemd/system/ipa-server-upgrade.service.d/50-success-poweroff.conf"
    mock_tasks_helper_shift_args 0
    run container_step_do_check_terminate_await
    assert_success
    assert_mock mkdir container_helper_link_to_power_off tasks_helper_shift_args utils_is_not_empty_str
    mock unstub mkdir container_helper_link_to_power_off tasks_helper_shift_args utils_is_not_empty_str
}


@test "container_step_enable_tracing - DEBUG_TRACE" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    export DEBUG_TRACE=1
    mock stub touch
    mock_touch 0 /run/ipa/debug-trace
    run container_step_enable_tracing
    assert_success
    assert_mock touch
    mock unstub touch
}


@test "container_step_enable_tracing - No DEBUG_TRACE" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    unset DEBUG_TRACE
    export DEBUG_TRACE
    mock stub touch
    run container_step_enable_tracing
    assert_success
    assert_mock touch
    mock unstub touch
}


@test "container_step_read_command - ipa-server-install" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    function helper_container_step_read_command {
        container_step_read_command
        [ "${COMMAND}" == "ipa-server-install" ]
    }
    export -f helper_container_step_read_command

    export ARGS=("ipa-server-install")
    mock stub tasks_helper_shift_args utils_is_not_empty_str
    mock_tasks_helper_shift_args 0
    mock_utils_is_not_empty_str 0 "${ARGS[0]}"
    run helper_container_step_read_command
    assert_success
    assert_mock tasks_helper_shift_args utils_is_not_empty_str
    mock unstub tasks_helper_shift_args utils_is_not_empty_str
}


@test "container_step_read_command - ipa-replica-install" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'


    function helper_container_step_read_command {
        container_step_read_command
        [ "${COMMAND}" == "ipa-replica-install" ]
    }
    export -f helper_container_step_read_command

    # export DATA="$( mktemp -d /tmp/mocks.XXXXXXXX )"
    export ARGS=("ipa-replica-install")
    mock stub tasks_helper_shift_args utils_is_not_empty_str
    mock_utils_is_not_empty_str 0 "${ARGS[0]}"
    mock_tasks_helper_shift_args 0
    run helper_container_step_read_command

    assert_success
    assert_mock tasks_helper_shift_args utils_is_not_empty_str
    mock unstub tasks_helper_shift_args utils_is_not_empty_str

    # if [ -z "${DATA}" ] && [ -d "${DATA}" ] && [ "${DATA}" != "/" ]; then
    #     /bin/rm -rf "${DATA}"
    # fi
}


@test "container_step_read_command - -options && not ipa-replica-install-options file" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'


    function helper_container_step_read_command {
        container_step_read_command
        [ "${COMMAND}" == "ipa-server-install" ]
    }
    export -f helper_container_step_read_command

    export DATA="$( mktemp -d /tmp/mocks.XXXXXXXX )"
    export ARGS=("-options")
    export COMMAND=""
    mock stub tasks_helper_shift_args utils_is_not_empty_str
    mock_utils_is_not_empty_str 0 "${ARGS[0]}"
    # mock_tasks_helper_shift_args 0
    run helper_container_step_read_command

    assert_success
    assert_mock tasks_helper_shift_args utils_is_not_empty_str
    mock unstub tasks_helper_shift_args utils_is_not_empty_str

    if [ -z "${DATA}" ] && [ -d "${DATA}" ] && [ "${DATA}" != "/" ]; then
        /bin/rm -rf "${DATA}"
    fi
}


@test "container_step_read_command - -options &&  ipa-replica-install-options file" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    function helper_container_step_read_command {
        container_step_read_command
        [ "${COMMAND}" == "ipa-replica-install" ]
    }
    export -f helper_container_step_read_command

    export DATA="$( mktemp -d /tmp/mocks.XXXXXXXX )"
    export ARGS=("-options")
    export COMMAND=""
    /bin/touch "${DATA}/ipa-replica-install-options"
    mock stub tasks_helper_shift_args utils_is_not_empty_str
    mock_utils_is_not_empty_str 0 "${ARGS[0]}"
    # mock_tasks_helper_shift_args 0
    run helper_container_step_read_command

    assert_success
    assert_mock tasks_helper_shift_args utils_is_not_empty_str
    mock unstub tasks_helper_shift_args utils_is_not_empty_str

    if [ -z "${DATA}" ] && [ -d "${DATA}" ] && [ "${DATA}" != "/" ]; then
        /bin/rm -rf "${DATA}"
    fi
}


@test "container_step_read_command - invalid" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'


    function helper_container_step_read_command {
        container_step_read_command
        [ "${COMMAND}" == "" ]
    }
    export -f helper_container_step_read_command

    # export DATA="$( mktemp -d /tmp/mocks.XXXXXXXX )"
    export ARGS=("invalid")
    mock stub tasks_helper_shift_args utils_is_not_empty_str
    mock_utils_is_not_empty_str 0 "${ARGS[0]}"
    # mock_tasks_helper_shift_args 0
    run helper_container_step_read_command

    assert_failure
    assert_mock tasks_helper_shift_args utils_is_not_empty_str
    mock unstub tasks_helper_shift_args utils_is_not_empty_str

    # if [ -z "${DATA}" ] && [ -d "${DATA}" ] && [ "${DATA}" != "/" ]; then
    #     rm -rf "${DATA}"
    # fi
}


@test "container_step_check_ipa_server_install_opts" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'


    export IPA_SERVER_INSTALL_OPTS="-U"
    export COMMAND="ipa-server-install"
    run container_step_check_ipa_server_install_opts
    assert_success

    export IPA_SERVER_INSTALL_OPTS="-U"
    export COMMAND="ipa-replica-install"
    run container_step_check_ipa_server_install_opts
    assert_success

    export IPA_SERVER_INSTALL_OPTS=""
    export COMMAND="ipa-server-install"
    run container_step_check_ipa_server_install_opts
    assert_success

    export IPA_SERVER_INSTALL_OPTS=""
    export COMMAND="ipa-replica-install"
    run container_step_check_ipa_server_install_opts
    assert_success

    export IPA_SERVER_INSTALL_OPTS=""
    export COMMAND="bash"
    run container_step_check_ipa_server_install_opts
    assert_success

    export IPA_SERVER_INSTALL_OPTS="-U"
    export COMMAND="bash"
    run container_step_check_ipa_server_install_opts
    assert_failure
    assert_equal "${status}" "7"
    assert_output "Invocation error: IPA_SERVER_INSTALL_OPTS should only be used with ipa-server-install or ipa-replica-install."
}


@test "container_step_set_options_file_vars" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    function helper_container_step_set_options_file_vars {
        export COMMAND="$1"
        export DATA="$2"
        container_step_set_options_file_vars
        assert_equal "${OPTIONS_FILE}" "/run/ipa/${COMMAND}-options"
        assert_equal "${DATA_OPTIONS_FILE}" "${DATA}/${COMMAND}-options"
    }
    export -f helper_container_step_set_options_file_vars

    run helper_container_step_set_options_file_vars "ipa-server-install" "/tmp"
    run helper_container_step_set_options_file_vars "ipa-replica-install" "/tmp"
}


# @test "container_step_print_out_option_file_content" {
#     source './init/utils.inc.sh'
#     source './init/tasks.inc.sh'
#     source './init/container.inc.sh'
# 
#     export OPTIONS_FILE=""
#     export DATA_OPTIONS_FILE=""
#     run container_step_print_out_option_file_content
#     assert_success
#     assert_output ""
# 
#     export OPTIONS_FILE="$( mktemp /tmp/container_step_print_out_option_file_content.options.XXXXXXXX )"
#     export DATA_OPTIONS_FILE="$( mktemp /tmp/container_step_print_out_option_file_content.data-options.XXXXXXXX )"
#     /bin/rm -f "${OPTIONS_FILE}"
#     /bin/rm -f "${DATA_OPTIONS_FILE}"
#     run container_step_print_out_option_file_content
#     assert_success
#     assert_output ""
# 
#     export OPTIONS_FILE="$( mktemp /tmp/container_step_print_out_option_file_content.options.XXXXXXXX )"
#     export DATA_OPTIONS_FILE="$( mktemp /tmp/container_step_print_out_option_file_content.data-options.XXXXXXXX )"
#     /bin/rm -f "${DATA_OPTIONS_FILE}"
#     run container_step_print_out_option_file_content
#     assert_success
#     assert_output "INFO:>> OPTIONS_FILE content: ${OPTIONS_FILE}"
#     /bin/rm -f "${OPTIONS_FILE}"
# 
#     export OPTIONS_FILE="$( mktemp /tmp/container_step_print_out_option_file_content.options.XXXXXXXX )"
#     export DATA_OPTIONS_FILE="$( mktemp /tmp/container_step_print_out_option_file_content.data-options.XXXXXXXX )"
#     /bin/rm -f "${DATA_OPTIONS_FILE}"
#     printf "This\nis\na\ntest\n" > "${OPTIONS_FILE}"
#     run container_step_print_out_option_file_content
#     assert_success
#     assert_output <<EOF
# INFO:>> OPTIONS_FILE content: ${OPTIONS_FILE}
# This
# is
# a
# test
# EOF
#     /bin/rm -f "${OPTIONS_FILE}"
# 
#     export OPTIONS_FILE="$( mktemp /tmp/container_step_print_out_option_file_content.options.XXXXXXXX )"
#     export DATA_OPTIONS_FILE="$( mktemp /tmp/container_step_print_out_option_file_content.data-options.XXXXXXXX )"
#     /bin/rm -f "${OPTIONS_FILE}"
#     run container_step_print_out_option_file_content
#     assert_success
#     assert_output "INFO:>> DATA_OPTIONS_FILE content: ${DATA_OPTIONS_FILE}"
#     /bin/rm -f "${DATA_OPTIONS_FILE}"
# 
#     export OPTIONS_FILE="$( mktemp /tmp/container_step_print_out_option_file_content.options.XXXXXXXX )"
#     export DATA_OPTIONS_FILE="$( mktemp /tmp/container_step_print_out_option_file_content.data-options.XXXXXXXX )"
#     /bin/rm -f "${OPTIONS_FILE}"
#     printf "This\nis\na\ntest\n" > "${DATA_OPTIONS_FILE}"
#     run container_step_print_out_option_file_content
#     assert_success
#     assert_output <<EOF
# INFO:>> DATA_OPTIONS_FILE content: ${DATA_OPTIONS_FILE}
# This
# is
# a
# test
# EOF
#     /bin/rm -f "${DATA_OPTIONS_FILE}"
# 
#     export OPTIONS_FILE="$( mktemp /tmp/container_step_print_out_option_file_content.options.XXXXXXXX )"
#     export DATA_OPTIONS_FILE="$( mktemp /tmp/container_step_print_out_option_file_content.data-options.XXXXXXXX )"
#     run container_step_print_out_option_file_content
#     assert_success
#     assert_output <<EOF
# INFO:>> OPTIONS_FILE content: ${OPTIONS_FILE}
# INFO:>> DATA_OPTIONS_FILE content: ${DATA_OPTIONS_FILE}
# EOF
#     /bin/rm -f "${OPTIONS_FILE}"
#     /bin/rm -f "${DATA_OPTIONS_FILE}"
# 
#     export OPTIONS_FILE="$( mktemp /tmp/container_step_print_out_option_file_content.options.XXXXXXXX )"
#     export DATA_OPTIONS_FILE="$( mktemp /tmp/container_step_print_out_option_file_content.data-options.XXXXXXXX )"
#     printf "This\nis\na\ntest\n" > "${OPTIONS_FILE}"
#     printf "This\nis\na\ntest\n" > "${DATA_OPTIONS_FILE}"
#     run container_step_print_out_option_file_content
#     assert_success
#     assert_output <<EOF
# INFO:>> OPTIONS_FILE content: ${OPTIONS_FILE}
# This
# is
# a
# test
# INFO:>> DATA_OPTIONS_FILE content: ${DATA_OPTIONS_FILE}
# This
# is
# a
# test
# EOF
#     /bin/rm -f "${OPTIONS_FILE}"
#     /bin/rm -f "${DATA_OPTIONS_FILE}"
# }


@test "container_step_fill_options_file" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    export OPTIONS_FILE="$( mktemp /tmp/container_step_fill_options_file.XXXX )"
    export ARGS=("1" "2" "3")
    mock stub touch chmod
    mock_touch 0 "${OPTIONS_FILE}"
    mock_chmod 0 600 "${OPTIONS_FILE}"
    run container_step_fill_options_file
    assert_success
    assert_mock touch chmod
    assert_output ""
    assert_equal "$( cat ${OPTIONS_FILE} )" '1
2
3'
    mock unstub touch chmod
    rm -f "${OPTIONS_FILE}"
}


@test "container_step_read_ipa_server_hostname_arg_from_options_file" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    mock stub container_helper_cat_options_file
    mock_container_helper_cat_options_file 0
    mock_container_helper_cat_options_file output <<EOF
--hostname
freeipa.test
EOF

    run container_step_read_ipa_server_hostname_arg_from_options_file

    assert_success
    assert_mock container_helper_cat_options_file
    mock unstub container_helper_cat_options_file
}


@test "container_helper_error_invoked_without_fqdn" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    run container_helper_error_invoked_without_fqdn
    assert_failure
    assert_output <<EOF
Container invoked without fully-qualified hostname
   and without specifying hostname to use.
Consider using -h FQDN option to docker run.
EOF
}

@test "container_step_process_hostname - no stored hostname" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    mock stub container_helper_exist_stored_hostname container_helper_store_hostname
    mock_container_helper_exist_stored_hostname 1
    export HOSTNAME="freeipa.test"
    mock_container_helper_exist_stored_hostname 1
    mock_container_helper_store_hostname 0 "${HOSTNAME}"

    run container_step_process_hostname

    assert_success
    assert_mock container_helper_exist_stored_hostname container_helper_store_hostname
    mock unstub container_helper_exist_stored_hostname container_helper_store_hostname
}


@test "container_step_process_hostname - no stored hostname and no fqdn" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    mock stub container_helper_exist_stored_hostname container_helper_store_hostname container_helper_error_invoked_without_fqdn
    mock_container_helper_exist_stored_hostname 1
    export HOSTNAME="freeipa"
    unset IPA_SERVER_HOSTNAME
    mock_container_helper_exist_stored_hostname 1
    mock_container_helper_store_hostname 0 "${HOSTNAME}"
    mock_container_helper_error_invoked_without_fqdn 15
    mock_container_helper_error_invoked_without_fqdn output <<EOF
Container invoked without fully-qualified hostname
and without specifying hostname to use.
Consider using -h FQDN option to docker run.
EOF
    run container_step_process_hostname

    assert_failure
    assert_output <<EOF
Container invoked without fully-qualified hostname
and without specifying hostname to use.
Consider using -h FQDN option to docker run.
EOF
    assert_mock container_helper_exist_stored_hostname container_helper_store_hostname container_helper_error_invoked_without_fqdn
    mock unstub container_helper_exist_stored_hostname container_helper_store_hostname container_helper_error_invoked_without_fqdn
}


@test "container_step_process_hostname - stored hostname and fqdn" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    mock stub container_helper_exist_stored_hostname container_helper_store_hostname container_helper_error_invoked_without_fqdn container_helper_cat_data_hostname
    mock_container_helper_exist_stored_hostname 0
    mock_container_helper_cat_data_hostname 0
    mock_container_helper_cat_data_hostname output <<EOF
freeipa.test
EOF
    export HOSTNAME="freeipa"
    unset IPA_SERVER_HOSTNAME
    mock_container_helper_exist_stored_hostname 1
    mock_container_helper_store_hostname 0 "freeipa.test"

    run container_step_process_hostname

    assert_success
    assert_mock container_helper_exist_stored_hostname container_helper_store_hostname container_helper_error_invoked_without_fqdn container_helper_cat_data_hostname
    mock unstub container_helper_exist_stored_hostname container_helper_store_hostname container_helper_error_invoked_without_fqdn container_helper_cat_data_hostname
}


@test "container_helper_exist_ca_cert - success" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    mock stub utils_is_a_file
    mock_utils_is_a_file 0 "/etc/ipa/ca.crt"

    run container_helper_exist_ca_cert

    assert_success
    assert_output ""
    assert_mock utils_is_a_file
    mock unstub utils_is_a_file
}


@test "container_helper_exist_ca_cert - failure" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    mock stub utils_is_a_file
    mock_utils_is_a_file 1 "/etc/ipa/ca.crt"

    run container_helper_exist_ca_cert

    assert_failure
    assert_output ""
    assert_mock utils_is_a_file
    mock unstub utils_is_a_file
}


@test "container_step_process_first_boot" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    mock stub container_helper_exist_ca_cert utils_is_a_file

    skip "TODO Not implemented"

}


@test "container_helper_create_machine_id - first boot" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    # First boot scenario
    export DATA="/data"
    mock stub container_helper_is_a_symlink container_helper_is_a_file dbus-uuidgen chmod
    mock_container_helper_is_a_symlink 0 "/etc/machine-id"
    mock_container_helper_is_a_file 1 "${DATA}/etc/machine-id"
    mock_dbus-uuidgen 0 --ensure=${DATA}/etc/machine-id
    mock_chmod 0 444 "${DATA}/etc/machine-id"
    run container_helper_create_machine_id
    assert_success
    assert_mock container_helper_is_a_symlink
    assert_mock container_helper_is_a_file
    assert_mock dbus-uuidgen
    assert_mock chmod
    mock unstub container_helper_is_a_symlink container_helper_is_a_file dbus-uuidgen chmod
}


@test "container_helper_create_machine_id - no first boot" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    # Other boots
    export DATA="/data"
    mock stub container_helper_is_a_symlink container_helper_is_a_file dbus-uuidgen chmod
    mock_container_helper_is_a_symlink 0 "/etc/machine-id"
    mock_container_helper_is_a_file 0 "${DATA}/etc/machine-id"
    run container_helper_create_machine_id
    assert_success
    assert_mock mock_container_helper_is_a_symlink
    assert_mock mock_container_helper_is_a_file
    assert_mock dbus-uuidgen chmod
    mock unstub container_helper_is_a_symlink container_helper_is_a_file dbus-uuidgen chmod
}


@test "container_step_upgrade_version" {
    skip "TODO It is not implemented"
}


@test "container_step_volume_update" {
    skip "TODO It is not implemented"
}


@test "container_step_print_out_timestamps_and_args" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    export LOGFILE_IPA_SERVER_CONFIGURE_FIRST=/dev/stdout
    export ARGS=("/usr/local/sbin/init" "no-exit" "-U")
    mock stub date
    mock_date 0
    run container_step_print_out_timestamps_and_args
    assert_success
    assert_output " /usr/local/sbin/init no-exit -U"
    assert_mock date
    mock unstub date
}


@test "container_step_do_show_log_if_enabled" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    local log_files=("/var/log/ipa-server-configure-first.log" "/var/log/ipa-server-run.log")

    mock stub touch container_helper_print_out_log
    for item in "${log_files[@]}"; do
        if ! [ -f "$item" ]; then 
            mock_touch 0 "${item}"
        fi
    done
    mock_container_helper_print_out_log 0
    run container_step_do_show_log_if_enabled
    assert_success
    assert_output ""
    assert_mock touch
    assert_mock container_helper_print_out_log
    mock unstub touch container_helper_print_out_log
}


@test "container_helper_write_ipa_server_ip_to_file" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    run container_helper_write_ipa_server_ip_to_file "10.10.10.1" "/dev/stdout"
    assert_success
    assert_output "10.10.10.1"

    run container_helper_write_ipa_server_ip_to_file
    assert_failure
    assert_output ""

    run container_helper_write_ipa_server_ip_to_file "10.10.10.1"
    assert_failure
    assert_output ""
}


@test "container_step_save_ipa_server_ip_if_provided - IPA_SERVER_IP provided" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    export IPA_SERVER_IP="10.10.10.1"
    mock stub container_helper_write_ipa_server_ip_to_file
    mock_container_helper_write_ipa_server_ip_to_file 0 "${IPA_SERVER_IP}" "/run/ipa/ipa-server-ip"

    run container_step_save_ipa_server_ip_if_provided

    assert_success
    assert_output ""
    assert_mock container_helper_write_ipa_server_ip_to_file
    mock unstub container_helper_write_ipa_server_ip_to_file
}


@test "container_step_save_ipa_server_ip_if_provided - IPA_SERVER_IP NOT provided" {
    source './init/utils.inc.sh'
    source './init/tasks.inc.sh'
    source './init/container.inc.sh'

    unset IPA_SERVER_IP
    mock stub container_helper_write_ipa_server_ip_to_file

    run container_step_save_ipa_server_ip_if_provided

    assert_success
    assert_output ""
    assert_mock container_helper_write_ipa_server_ip_to_file
    mock unstub container_helper_write_ipa_server_ip_to_file
}


# TODO Clean-up this test
# @test "container_step_print_out_env_if_debug - No DEBUG_TRACE" {
#     source './init/utils.inc.sh'
#     source './init/tasks.inc.sh'
#     source './init/container.inc.sh'
# 
#     export DEBUG_TRACE=
#     mock stub env
#     run container_step_print_out_env_if_debug
#     assert_success
#     assert_output ""
#     assert_mock env
#     mock unstub env
# }


# TODO Clean-up this test
# @test "container_step_print_out_env_if_debug - DEBUG_TRACE" {
#     source './init/utils.inc.sh'
#     source './init/tasks.inc.sh'
#     source './init/container.inc.sh'
# 
#     export DEBUG_TRACE=1
#     mock stub env
#     mock_env 0
#     run container_step_print_out_env_if_debug
#     assert_success
#     assert_output ""
#     assert_mock env
#     mock unstub env
# }


@test "container_step_exec_init" {
    skip "TODO This function can not be implemented as unit test"
}
