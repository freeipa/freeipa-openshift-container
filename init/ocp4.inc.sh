#!/bin/bash

function ocp4_step_enable_traces
{
    test -z "$DEBUG_TRACE" || {
        if [ "${DEBUG_TRACE}" == "2" ]; then
            export SYSTEMD_LOG_LEVEL="debug"
            export SYSTEMD_LOG_TARGET="journal+console"
            export SYSTEMD_LOG_COLOR="no"
            export DEBUG=1
        fi
        # Turn on tracing of this script
        set -x
    }
}

function ocp4_helper_switch_starting_by_substr
{
    local _starting="$1"
    local _substr="$2"
    local _filename="$3"
    sed -i "s/^${_starting}/${_substr}/g" "${_filename}"
}

function ocp4_step_systemd_units_set_private_devices_off
{
    ocp4_helper_switch_starting_by_substr "PrivateDevices=true" "PrivateDevices=off" "/usr/lib/systemd/system/dbus-broker.service"
}

function ocp4_step_systemd_units_set_private_system_off
{
    # FIXME Clean-up
    # sed -i "s/^ProtectSystem=full/# ProtectSystem=full/g" "/usr/lib/systemd/system/dbus-broker.service"
    ocp4_helper_switch_starting_by_substr "ProtectSystem=full" "# ProtectSystem=full" "/usr/lib/systemd/system/dbus-broker.service"
}

function ocp4_helper_turn_private_tmp_off
{
    for _filename in "$@"; do
        [ -e "${_filename}" ] || return 1
        sed -i \
            -e s/^PrivateTmp=on/PrivateTmp=off/g \
            -e s/^PrivateTmp=yes/PrivateTmp=off/g \
            -e s/^PrivateTmp=true/PrivateTmp=off/g \
            "${_filename}"
    done
}

function ocp4_step_systemd_units_set_private_tmp_off
{
    # Disable PrivateTmp
    # FIXME Clean-up
    # sed -i s/^PrivateTmp=on/PrivateTmp=off/g /lib/systemd/system/dirsrv@.service
    # sed -i s/^PrivateTmp=yes/PrivateTmp=off/g /lib/systemd/system/ipa-custodia.service
    # sed -i s/^PrivateTmp=true/PrivateTmp=off/g /usr/lib/systemd/system/dbus-broker.service
    # sed -i s/^PrivateTmp=true/PrivateTmp=off/g /lib/systemd/system/httpd.service
    # sed -i s/^PrivateTmp=yes/PrivateTmp=off/g /lib/systemd/system/chronyd.service
    # sed -i s/^PrivateTmp=yes/PrivateTmp=off/g /lib/systemd/system/dbus-org.freedesktop.hostname1.service
    # sed -i s/^PrivateTmp=yes/PrivateTmp=off/g /lib/systemd/system/dbus-org.freedesktop.locale1.service
    # sed -i s/^PrivateTmp=yes/PrivateTmp=off/g /lib/systemd/system/dbus-org.freedesktop.login1.service
    # sed -i s/^PrivateTmp=yes/PrivateTmp=off/g /lib/systemd/system/dbus-org.freedesktop.oom1.service
    # sed -i s/^PrivateTmp=yes/PrivateTmp=off/g /lib/systemd/system/dbus-org.freedesktop.timedate1.service
    # sed -i s/^PrivateTmp=yes/PrivateTmp=off/g /lib/systemd/system/ipa-ccache-sweep.service
    # sed -i s/^PrivateTmp=yes/PrivateTmp=off/g /lib/systemd/system/ipa-dnskeysyncd.service
    # sed -i s/^PrivateTmp=yes/PrivateTmp=off/g /lib/systemd/system/ipa-ods-exporter.service
    # sed -i s/^PrivateTmp=yes/PrivateTmp=off/g /lib/systemd/system/systemd-coredump@.service
    # sed -i s/^PrivateTmp=yes/PrivateTmp=off/g /lib/systemd/system/systemd-hostnamed.service
    # sed -i s/^PrivateTmp=yes/PrivateTmp=off/g /lib/systemd/system/systemd-localed.service
    # sed -i s/^PrivateTmp=yes/PrivateTmp=off/g /lib/systemd/system/systemd-logind.service
    # sed -i s/^PrivateTmp=yes/PrivateTmp=off/g /lib/systemd/system/systemd-oomd.service
    # sed -i s/^PrivateTmp=yes/PrivateTmp=off/g /lib/systemd/system/systemd-resolved.service
    # sed -i s/^PrivateTmp=yes/PrivateTmp=off/g /lib/systemd/system/systemd-timedated.service
    # sed -i s/^PrivateTmp=true/PrivateTmp=off/g /lib/systemd/system/logrotate.service
    # sed -i s/^PrivateTmp=true/PrivateTmp=off/g /lib/systemd/system/named.service
    # sed -i s/^PrivateTmp=true/PrivateTmp=off/g /lib/systemd/system/httpd@.service

    ocp4_helper_turn_private_tmp_off /lib/systemd/system/dirsrv@.service \
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
}

function ocp4_step_process_hostname
{
	# Container is run without FQDN set, we try to "set" it in /etc/hosts
	if ! grep -q "${IPA_SERVER_HOSTNAME}" /etc/hosts; then
		cp /etc/hosts /etc/hosts.dist
		sed "s/${HOSTNAME}/${IPA_SERVER_HOSTNAME} ${IPA_SERVER_HOSTNAME}. &/" /etc/hosts.dist > /etc/hosts
		rm -f /etc/hosts.dist
	fi
	HOSTNAME=${IPA_SERVER_HOSTNAME}

    if ! [ -f "${DATA}/hostname" ] ; then
        echo "${HOSTNAME}" > "${DATA}/hostname"
    fi
}

OCP4_LIST_TASKS=()
# +ocp4:begin-list
OCP4_LIST_TASKS+=("ocp4_step_systemd_units_set_private_tmp_off")
OCP4_LIST_TASKS+=("ocp4_step_systemd_units_set_private_system_off")
OCP4_LIST_TASKS+=("ocp4_step_systemd_units_set_private_devices_off")
# +ocp4:end-list

tasks_helper_update_step \
    "container_step_enable_traces" \
    "ocp4_step_enable_traces"

tasks_helper_update_step \
    "container_step_process_hostname" \
    "ocp4_step_process_hostname"

tasks_helper_add_after \
    "container_step_volume_update" \
    "${OCP4_LIST_TASKS[@]}"

