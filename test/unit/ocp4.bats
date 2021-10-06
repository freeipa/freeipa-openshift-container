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
    mock_tasks_helper_add_after 0 "container_step_volume_update" \
                                  "ocp4_step_systemd_units_set_private_tmp_off" \
                                  "ocp4_step_systemd_units_set_private_system_off" \
                                  "ocp4_step_systemd_units_set_private_devices_off"
}

function teardown
{
    mock unstub tasks_helper_update_step tasks_helper_add_after
}

@test "ocp4_step_enable_traces" {

    source './init/ocp4.inc.sh'

    function helper_enable_traces {
        ocp4_step_enable_traces
        if [ "${DEBUG_TRACE}" != "" ]; then
            shopt -q -o xtrace || return 1
            if [ "${DEBUG_TRACE}" == "2" ]; then
                [ "${SYSTEMD_LOG_LEVEL}" == "debug" ] || return 2
                [ "${SYSTEMD_LOG_TARGET}" == "journal+console" ] || return 3
                [ "${SYSTEMD_LOG_COLOR}" == "no" ] || return 4
                [ "${DEBUG}" == "1" ] || return 5
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


@test "ocp4_step_systemd_units_set_private_tmp_off" {
    source './init/ocp4.inc.sh'

    mock stub ocp4_helper_turn_private_tmp_off
    mock_ocp4_helper_turn_private_tmp_off 0 /lib/systemd/system/dirsrv@.service \
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
