#!/bin/bash

# Directory Manager Password
IPA_DM_PASSWORD="${IPA_DM_PASSWORD:-${PASSWORD}}"

# Freeipa admin passowrd
IPA_ADMIN_PASSWORD="${IPA_ADMIN_PASSWORD:-${PASSWORD}}"

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

function ocp4_step_systemd_tmpfiles_create
{
    systemd-tmpfiles --create
}

function ocp4_helper_write_to_options_file
{
    printf '%q\n' "$1" >> "${OPTIONS_FILE}"
}

function ocp4_helper_has_principal_arg
{
    grep -sq '^--principal' "${OPTIONS_FILE}" "${DATA_OPTIONS_FILE}"
}

function ocp4_helper_has_ds_password_arg
{
    grep -sq '^--ds-password' "${OPTIONS_FILE}" "${DATA_OPTIONS_FILE}"
}

function ocp4_helper_process_password_admin_password
{
    # Freeipa admin password
    if [ -n "${IPA_ADMIN_PASSWORD}" ]; then
        if [ "${COMMAND}" == 'ipa-server-install' ] ; then
            # printf '%q\n' "--admin-password=${IPA_ADMIN_PASSWORD}" >> "${OPTIONS_FILE}"
            ocp4_helper_write_to_options_file "--admin-password=${IPA_ADMIN_PASSWORD}"
        elif [ "${COMMAND}" == "ipa-replica-install" ]; then
            if ocp4_helper_has_principal_arg; then
                # printf '%q\n' "--admin-password=${IPA_ADMIN_PASSWORD}" >> "${OPTIONS_FILE}"
                ocp4_helper_write_to_options_file "--admin-password=${IPA_ADMIN_PASSWORD}"
            else
                # printf '%q\n' "--password=${IPA_ADMIN_PASSWORD}" >> "${OPTIONS_FILE}"
                ocp4_helper_write_to_options_file "--password=${IPA_ADMIN_PASSWORD}"
            fi
        else
            tasks_helper_msg_warning "Ignoring environment variable IPA_ADMIN_PASSWORD."
        fi
    fi
}

function ocp4_helper_process_password_dm_password
{
    # Directory manager password
    if [ -n "${IPA_DM_PASSWORD}" ]; then
        if [ "${COMMAND}" == 'ipa-server-install' ]; then
            if ! ocp4_helper_has_ds_password_arg; then
                # printf '%q\n' "--ds-password=${IPA_DM_PASSWORD}" >> "${OPTIONS_FILE}"
                ocp4_helper_write_to_options_file "--ds-password=${IPA_DM_PASSWORD}"
            fi
        elif [ "${COMMAND}" == "ipa-replica-install" ]; then
            tasks_helper_msg_info "IPA_DM_PASSWORD not used for replicas."
        else
            tasks_helper_msg_warning "Ignoring environment variable IPA_DM_PASSWORD."
        fi
    fi
}

function ocp4_helper_process_password
{
    ocp4_helper_process_password_admin_password
    ocp4_helper_process_password_dm_password
}

function ocp4_step_process_first_boot
{
    if ! container_helper_exist_ca_cert ; then
        if ! utils_is_a_file "${DATA}/ipa.csr" ; then
            # Do not refresh $DATA in the second stage of the external CA setup
            /usr/local/bin/populate-volume-from-template "${DATA}"
            container_helper_create_machine_id
        fi

        ocp4_helper_process_password

        if [ -n "$IPA_SERVER_INSTALL_OPTS" ] ; then
            # FIXME Fix this shellcheck hint when refactoring this
            #       function for unit tests
            # shellcheck disable=SC2166
            if [ "$COMMAND" == 'ipa-server-install' -o "$COMMAND" = 'ipa-replica-install' ] ; then
                echo "$IPA_SERVER_INSTALL_OPTS" >> "$OPTIONS_FILE"
            else
                echo "Warning: ignoring environment variable IPA_SERVER_INSTALL_OPTS." >&2
            fi
        fi

        if [ -n "${DEBUG}" ] ; then
            echo "--debug" >> "${OPTIONS_FILE}"
        fi
    fi
}


OCP4_LIST_TASKS=()
# +ocp4:begin-list
OCP4_LIST_TASKS+=("ocp4_step_systemd_units_set_private_tmp_off")
OCP4_LIST_TASKS+=("ocp4_step_systemd_units_set_private_system_off")
OCP4_LIST_TASKS+=("ocp4_step_systemd_units_set_private_devices_off")
OCP4_LIST_TASKS+=("ocp4_step_systemd_tmpfiles_create")
# +ocp4:end-list

tasks_helper_update_step \
    "container_step_enable_traces" \
    "ocp4_step_enable_traces"

tasks_helper_update_step \
    "container_step_process_hostname" \
    "ocp4_step_process_hostname"

tasks_helper_update_step \
    "container_step_process_first_boot" \
    "ocp4_step_process_first_boot"

tasks_helper_add_after \
    "container_step_volume_update" \
    "${OCP4_LIST_TASKS[@]}"

