#!/usr/bin/env bats

# https://opensource.com/article/19/2/testing-bash-bats

load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../libs/bats-mock/load'


function setup
{
    mock stub tasks_helper_update_step tasks_helper_add_after
    mock_tasks_helper_update_step 0 "container_step_enable_traces" \
                                    "ocp4_step_enable_traces"
    mock_tasks_helper_update_step 0 "container_step_process_hostname" \
                                    "ocp4_step_process_hostname"
    mock_tasks_helper_update_step 0 \
        "container_step_process_first_boot" \
        "ocp4_step_process_first_boot"

    mock_tasks_helper_add_after 0 "container_step_volume_update" \
                                  "ocp4_step_systemd_units_set_private_tmp_off" \
                                  "ocp4_step_systemd_units_set_private_system_off" \
                                  "ocp4_step_systemd_units_set_private_devices_off" \
                                  "ocp4_step_systemd_tmpfiles_create"
}


function teardown
{
    mock unstub tasks_helper_update_step tasks_helper_add_after
}


@test "ocp4_helper_process_password_admin_password" {
    source './init/ocp4.inc.sh'
    local _mocks=()
    _mocks+=("ocp4_helper_write_to_options_file")
    _mocks+=("ocp4_helper_has_principal_arg")
    _mocks+=("tasks_helper_msg_warning")
    _mocks+=("tasks_helper_error")

    # No admin password
    unset COMMAND
    unset IPA_ADMIN_PASSWORD
    export IPA_ADMIN_PASSWORD COMMAND
    mock stub "${_mocks[@]}"
    run ocp4_helper_process_password_admin_password
    assert_success
    assert_output ""
    assert_mock "${_mocks[@]}"
    mock unstub "${_mocks[@]}"

    # Admin password and ipa-server-install
    IPA_ADMIN_PASSWORD="Secret123"
    COMMAND="ipa-server-install"
    export IPA_ADMIN_PASSWORD COMMAND
    mock stub "${_mocks[@]}"
    mock_ocp4_helper_write_to_options_file 0 "--admin-password=${IPA_ADMIN_PASSWORD}"
    run ocp4_helper_process_password_admin_password
    assert_success
    assert_output ""
    assert_mock "${_mocks[@]}"
    mock unstub "${_mocks[@]}"

    # Admins password, ipa-replica-install and --principal
    IPA_ADMIN_PASSWORD="Secret123"
    COMMAND="ipa-replica-install"
    export IPA_ADMIN_PASSWORD COMMAND
    mock stub "${_mocks[@]}"
    mock_ocp4_helper_has_principal_arg 0
    mock_ocp4_helper_write_to_options_file 0 "--admin-password=${IPA_ADMIN_PASSWORD}"
    run ocp4_helper_process_password_admin_password
    assert_success
    assert_output ""
    assert_mock "${_mocks[@]}"
    mock unstub "${_mocks[@]}"

    # Admins password, ipa-replica-install and without --principal
    IPA_ADMIN_PASSWORD="Secret123"
    COMMAND="ipa-replica-install"
    export IPA_ADMIN_PASSWORD COMMAND
    mock stub "${_mocks[@]}"
    mock_tasks_helper_error 1 "--principal option is required for container ipa-replica-install command"
    mock_ocp4_helper_has_principal_arg 1
    run ocp4_helper_process_password_admin_password
    assert_failure
    assert_output ""
    assert_mock "${_mocks[@]}"
    mock unstub "${_mocks[@]}"

    # Admin password but no ipa-*-install command
    IPA_ADMIN_PASSWORD="Secret123"
    COMMAND="bash"
    export IPA_ADMIN_PASSWORD COMMAND
    mock stub "${_mocks[@]}"
    mock_tasks_helper_msg_warning 0 "Ignoring environment variable IPA_ADMIN_PASSWORD."
    mock_tasks_helper_msg_warning output <<< "INFO:Ignoring environment variable IPA_ADMIN_PASSWORD."
    run ocp4_helper_process_password_admin_password
    assert_success
    assert_output <<< "INFO:Ignoring environment variable IPA_ADMIN_PASSWORD."
    assert_mock "${_mocks[@]}"
    mock unstub "${_mocks[@]}"
}


@test "ocp4_helper_process_password_dm_password" {
    source './init/ocp4.inc.sh'
    local _mocks=()
    _mocks+=("ocp4_helper_has_ds_password_arg")
    _mocks+=("ocp4_helper_write_to_options_file")
    _mocks+=("tasks_helper_msg_info")
    _mocks+=("tasks_helper_msg_warning")

    # No dm password
    unset COMMAND
    unset IPA_DM_PASSWORD
    export IPA_DM_PASSWORD COMMAND
    mock stub "${_mocks[@]}"
    run ocp4_helper_process_password_dm_password
    assert_success
    assert_output ""
    assert_mock "${_mocks[@]}"
    mock unstub "${_mocks[@]}"

    # DM password and ipa-server-install and NOT HAS --ds-password
    IPA_DM_PASSWORD="Secret123"
    COMMAND="ipa-server-install"
    export IPA_DM_PASSWORD COMMAND
    mock stub "${_mocks[@]}"
    mock_ocp4_helper_has_ds_password_arg 1
    mock_ocp4_helper_write_to_options_file 0 "--ds-password=${IPA_DM_PASSWORD}"
    run ocp4_helper_process_password_dm_password
    assert_success
    assert_output ""
    assert_mock "${_mocks[@]}"
    mock unstub "${_mocks[@]}"

    # DM password and ipa-server-install and HAS --ds-password
    IPA_DM_PASSWORD="Secret123"
    COMMAND="ipa-server-install"
    export IPA_DM_PASSWORD COMMAND
    mock stub "${_mocks[@]}"
    mock_ocp4_helper_has_ds_password_arg 0
    run ocp4_helper_process_password_dm_password
    assert_success
    assert_output ""
    assert_mock "${_mocks[@]}"
    mock unstub "${_mocks[@]}"

    # DM password and ipa-replica-install
    IPA_DM_PASSWORD="Secret123"
    COMMAND="ipa-replica-install"
    export IPA_DM_PASSWORD COMMAND
    mock stub "${_mocks[@]}"
    mock_tasks_helper_msg_info 0 "IPA_DM_PASSWORD not used for replicas."
    mock_tasks_helper_msg_info output <<< "INFO:IPA_DM_PASSWORD not used for replicas."
    run ocp4_helper_process_password_dm_password
    assert_success
    assert_output <<< "INFO:IPA_DM_PASSWORD not used for replicas."
    assert_mock "${_mocks[@]}"
    mock unstub "${_mocks[@]}"

    # DM password and other command
    IPA_DM_PASSWORD="Secret123"
    COMMAND="bash"
    export IPA_DM_PASSWORD COMMAND
    mock stub "${_mocks[@]}"
    mock_tasks_helper_msg_warning 0 "Ignoring environment variable IPA_DM_PASSWORD."
    mock_tasks_helper_msg_warning output <<< "WARNING:Ignoring environment variable IPA_DM_PASSWORD."
    run ocp4_helper_process_password_dm_password
    assert_success
    assert_output <<< "WARNING:Ignoring environment variable IPA_DM_PASSWORD."
    assert_mock "${_mocks[@]}"
    mock unstub "${_mocks[@]}"
}


@test "ocp4_helper_process_password" {
    source './init/ocp4.inc.sh'
    local _mocks=()
    _mocks+=("ocp4_helper_process_password_admin_password")
    _mocks+=("ocp4_helper_process_password_dm_password")

    mock stub "${_mocks[@]}"
    mock_ocp4_helper_process_password_admin_password 0
    mock_ocp4_helper_process_password_dm_password 0
    run ocp4_helper_process_password
    assert_success
    assert_output <<< ""
    assert_mock "${_mocks[@]}"
    mock unstub "${_mocks[@]}"
}


@test "ocp4_step_enable_traces" {

    source './init/ocp4.inc.sh'

    function helper_enable_traces {
        ocp4_step_enable_traces
        if [ "${DEBUG_TRACE}" != "" ]; then
            shopt -q -o xtrace || return 1
            if [ "${DEBUG_TRACE}" == "2" ]; then
                [ "${SYSTEMD_LOG_LEVEL}" == "debug" ] || return 2
                [ "${SYSTEMD_LOG_COLOR}" == "no" ] || return 3
                [ "${DEBUG}" == "1" ] || return 4
            fi
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

    DEBUG_TRACE=2
    run helper_enable_traces
    assert_success
}


@test "ocp4_step_systemd_units_set_private_devices_off" {
    source './init/ocp4.inc.sh'

    mock stub ocp4_helper_switch_starting_by_substr
    mock_ocp4_helper_switch_starting_by_substr 0 "PrivateDevices=true" "PrivateDevices=off" "/usr/lib/systemd/system/dbus-broker.service"
    run ocp4_step_systemd_units_set_private_devices_off

    assert_mock ocp4_helper_switch_starting_by_substr
    assert_success
}


@test "ocp4_step_systemd_units_set_private_system_off" {
    source './init/ocp4.inc.sh'

    mock stub ocp4_helper_switch_starting_by_substr
    mock_ocp4_helper_switch_starting_by_substr 0 "ProtectSystem=full" "# ProtectSystem=full" "/usr/lib/systemd/system/dbus-broker.service"
    run ocp4_step_systemd_units_set_private_system_off

    assert_mock ocp4_helper_switch_starting_by_substr
    assert_success
    mock unstub ocp4_helper_switch_starting_by_substr
}


@test "ocp4_helper_turn_private_tmp_off_for_one_file" {
    source './init/ocp4.inc.sh'

    local _filename="/tmp/systemd.unit"
    mock stub ocp4_helper_switch_starting_by_substr
    mock_ocp4_helper_switch_starting_by_substr 0 "PrivateTmp=on" "PrivateTmp=off" "${_filename}"
    mock_ocp4_helper_switch_starting_by_substr 0 "PrivateTmp=yes" "PrivateTmp=off" "${_filename}"
    mock_ocp4_helper_switch_starting_by_substr 0 "PrivateTmp=true" "PrivateTmp=off" "${_filename}"

    run ocp4_helper_turn_private_tmp_off_for_one_file "${_filename}"
    assert_success
    assert_output ""
    assert_mock ocp4_helper_switch_starting_by_substr
    mock unstub ocp4_helper_switch_starting_by_substr
}


@test "ocp4_helper_turn_private_tmp_off - no files" {
    source './init/ocp4.inc.sh'

    local _filename=()
    mock stub utils_path_exists tasks_helper_msg_warning ocp4_helper_turn_private_tmp_off_for_one_file


    run ocp4_helper_turn_private_tmp_off "${_filename[@]}"
    assert_success
    assert_output ""
    assert_mock utils_path_exists tasks_helper_msg_warning ocp4_helper_turn_private_tmp_off_for_one_file
    mock unstub utils_path_exists tasks_helper_msg_warning ocp4_helper_turn_private_tmp_off_for_one_file
}


@test "ocp4_helper_turn_private_tmp_off - a file that does not exist" {
    source './init/ocp4.inc.sh'

    local _filename=("/tmp/does_not_exist")
    mock stub utils_path_exists tasks_helper_msg_warning ocp4_helper_turn_private_tmp_off_for_one_file
    mock_utils_path_exists 1 "${_filename[0]}"
    local _msg="File '${_filename[0]}' not found at 'ocp4_helper_turn_private_tmp_off'"
    mock_tasks_helper_msg_warning 0 "${_msg}"
    mock_tasks_helper_msg_warning output <<EOF
WARNING:${_msg}
EOF

    run ocp4_helper_turn_private_tmp_off "${_filename[@]}"
    assert_success
    assert_output "WARNING:${_msg}"
    assert_mock utils_path_exists tasks_helper_msg_warning ocp4_helper_turn_private_tmp_off_for_one_file
    mock unstub utils_path_exists tasks_helper_msg_warning ocp4_helper_turn_private_tmp_off_for_one_file
}


@test "ocp4_helper_turn_private_tmp_off - a file that exist" {
    source './init/ocp4.inc.sh'

    local _filename=("/tmp/does_exist_1")
    mock stub utils_path_exists tasks_helper_msg_warning ocp4_helper_turn_private_tmp_off_for_one_file
    mock_utils_path_exists 0 "${_filename[0]}"
    mock_ocp4_helper_turn_private_tmp_off_for_one_file 0 "${_filename[0]}"

    run ocp4_helper_turn_private_tmp_off "${_filename[@]}"
    assert_success
    assert_output ""
    assert_mock utils_path_exists tasks_helper_msg_warning ocp4_helper_turn_private_tmp_off_for_one_file
    mock unstub utils_path_exists tasks_helper_msg_warning ocp4_helper_turn_private_tmp_off_for_one_file
}


@test "ocp4_helper_turn_private_tmp_off - several files that exist" {
    source './init/ocp4.inc.sh'

    local _filename=("/tmp/does_exist_1" "/tmp/does_exist_2")
    mock stub utils_path_exists tasks_helper_msg_warning ocp4_helper_turn_private_tmp_off_for_one_file
    mock_utils_path_exists 0 "${_filename[0]}"
    mock_utils_path_exists 0 "${_filename[1]}"
    mock_ocp4_helper_turn_private_tmp_off_for_one_file 0 "${_filename[0]}"
    mock_ocp4_helper_turn_private_tmp_off_for_one_file 0 "${_filename[1]}"

    run ocp4_helper_turn_private_tmp_off "${_filename[@]}"
    assert_success
    assert_output ""
    assert_mock utils_path_exists tasks_helper_msg_warning ocp4_helper_turn_private_tmp_off_for_one_file
    mock unstub utils_path_exists tasks_helper_msg_warning ocp4_helper_turn_private_tmp_off_for_one_file
}


@test "ocp4_step_systemd_units_set_private_tmp_off" {
    source './init/ocp4.inc.sh'

    mock stub ocp4_helper_turn_private_tmp_off
    mock_ocp4_helper_turn_private_tmp_off 0 \
        /lib/systemd/system/dirsrv@.service \
        /lib/systemd/system/ipa-custodia.service \
        /usr/lib/systemd/system/dbus-broker.service \
        /lib/systemd/system/httpd.service \
        /lib/systemd/system/chronyd.service \
        /lib/systemd/system/dbus-org.freedesktop.hostname1.service \
        /lib/systemd/system/dbus-org.freedesktop.locale1.service \
        /lib/systemd/system/dbus-org.freedesktop.login1.service \
        /lib/systemd/system/dbus-org.freedesktop.oom1.service \
        /lib/systemd/system/dbus-org.freedesktop.timedate1.service \
        /lib/systemd/system/ipa-ccache-sweep.service \
        /lib/systemd/system/ipa-dnskeysyncd.service \
        /lib/systemd/system/ipa-ods-exporter.service \
        /lib/systemd/system/systemd-coredump@.service \
        /lib/systemd/system/systemd-hostnamed.service \
        /lib/systemd/system/systemd-localed.service \
        /lib/systemd/system/systemd-logind.service \
        /lib/systemd/system/systemd-oomd.service \
        /lib/systemd/system/systemd-resolved.service \
        /lib/systemd/system/systemd-timedated.service \
        /lib/systemd/system/logrotate.service \
        /lib/systemd/system/named.service \
        /lib/systemd/system/httpd@.service

    run ocp4_step_systemd_units_set_private_tmp_off
    assert_success
    assert_mock ocp4_helper_turn_private_tmp_off \
                tasks_helper_update_step \
                tasks_helper_add_after

    mock unstub ocp4_helper_turn_private_tmp_off
}


@test "ocp4_step_process_hostname" {
    source './init/ocp4.inc.sh'
    skip "TODO Not implemented"
}
