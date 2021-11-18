#!/usr/bin/env bats

# https://opensource.com/article/19/2/testing-bash-bats

load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../libs/bats-mock/load'


function setup
{
    mock stub tasks_helper_update_step tasks_helper_add_after tasks_helper_add_before
    mock_tasks_helper_update_step 0 "container_step_enable_traces" \
                                    "ocp4_step_enable_traces"
    mock_tasks_helper_update_step 0 "container_step_process_hostname" \
                                    "ocp4_step_process_hostname"
    mock_tasks_helper_add_after 0 "container_step_volume_update" \
                                  "ocp4_step_systemd_units_set_private_tmp_off" \
                                  "ocp4_step_systemd_units_set_private_system_off" \
                                  "ocp4_step_systemd_units_set_private_devices_off" \
                                  "ocp4_step_enable_httpd_service"
}

function teardown
{
    mock unstub tasks_helper_update_step tasks_helper_add_after tasks_helper_add_before
}


@test "ocp4_step_enable_httpd_service" {
    source './init/ocp4.inc.sh'


    mock stub systemctl container_helper_exist_ca_cert
    mock_container_helper_exist_ca_cert 1
    run ocp4_step_enable_httpd_service
    assert_success
    assert_output ""
    assert_mock systemctl container_helper_exist_ca_cert
    mock unstub systemctl container_helper_exist_ca_cert


    mock stub systemctl container_helper_exist_ca_cert
    mock_container_helper_exist_ca_cert 0
    mock_systemctl 0 enable httpd
    mock_systemctl output <<EOF
Created symlink /etc/systemd/system/multi-user.target.wants/httpd.service → /usr/lib/systemd/system/httpd.service.
EOF
    run ocp4_step_enable_httpd_service
    assert_success
    assert_output <<EOF
Created symlink /etc/systemd/system/multi-user.target.wants/httpd.service → /usr/lib/systemd/system/httpd.service.
EOF
    assert_mock systemctl container_helper_exist_ca_cert
    mock unstub systemctl container_helper_exist_ca_cert

    # After enable, the output is empty
    mock stub systemctl container_helper_exist_ca_cert
    mock_container_helper_exist_ca_cert 0
    mock_systemctl 0 enable httpd
    run ocp4_step_enable_httpd_service
    assert_success
    assert_output ""
    assert_mock systemctl container_helper_exist_ca_cert
    mock unstub systemctl container_helper_exist_ca_cert
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
