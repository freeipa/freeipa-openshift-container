#!/bin/bash

function ocp4_step_enable_traces
{
    test -z "$DEBUG_TRACE" || {
        if [ "${DEBUG_TRACE}" == "2" ]; then
            export SYSTEMD_LOG_LEVEL="debug"
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

function ocp4_helper_turn_private_tmp_off_for_one_file
{
    local _filename="$1"
    ocp4_helper_switch_starting_by_substr "PrivateTmp=on" "PrivateTmp=off" "${_filename}"
    ocp4_helper_switch_starting_by_substr "PrivateTmp=yes" "PrivateTmp=off" "${_filename}"
    ocp4_helper_switch_starting_by_substr "PrivateTmp=true" "PrivateTmp=off" "${_filename}"
}

function ocp4_helper_turn_private_tmp_off
{
    for _filename in "$@"; do
        utils_path_exists "${_filename}" || {
            tasks_helper_msg_warning "File '${_filename}' not found at '${FUNCNAME[0]}'"
            continue
        }
        ocp4_helper_turn_private_tmp_off_for_one_file "${_filename}"
    done
}

# FIXME PrivateTmp=true allow that other services does not have access to other
#       software's temporary files.
#
#       This function it is only a workaround to let the container run, but this
#       is not the right solution.
#
#       For systemd workloads with PrivateTmp=on should be possible to run.
#
#       Create a seccomp profile which could allow to call mount system call
#       only for the specific fstype and for the command subpath that is
#       used to mount the temprary file system.
#
#       More information about building seccomp profiles for kubernetes:
#       https://kubernetes.io/docs/tutorials/clusters/seccomp/#create-seccomp-profiles
#
#       Other syscalls could be needed.
function ocp4_step_systemd_units_set_private_tmp_off
{
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

function ocp4_step_enable_httpd_service
{
    if container_helper_exist_ca_cert; then
        systemctl is-enabled httpd || systemctl enable httpd
    fi
}

OCP4_LIST_TASKS=()
# +ocp4:begin-list
OCP4_LIST_TASKS+=("ocp4_step_systemd_units_set_private_tmp_off")
OCP4_LIST_TASKS+=("ocp4_step_systemd_units_set_private_system_off")
OCP4_LIST_TASKS+=("ocp4_step_systemd_units_set_private_devices_off")
OCP4_LIST_TASKS+=("ocp4_step_enable_httpd_service")
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
