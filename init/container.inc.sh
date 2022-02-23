#!/bin/bash

# It is assumed tasks.inc.sh is included

DATA=/data
DATA_TEMPLATE=/data-template
COMMAND=
OPTIONS_FILE=
DATA_OPTIONS_FILE=
# shellcheck disable=SC2269
IPA_SERVER_HOSTNAME="${IPA_SERVER_HOSTNAME}"
# shellcheck disable=SC2269
HOSTNAME="${HOSTNAME}"
# shellcheck disable=SC2269
IPA_SERVER_IP="${IPA_SERVER_IP}"
# shellcheck disable=SC2269
SYSTEMD_OPTS="${SYSTEMD_OPTS}"
LOGFILE_IPA_SERVER_CONFIGURE_FIRST="/var/log/ipa-server-configure-first.log"
LOGFILE_IPA_SERVER_RUN="/var/log/ipa-server-run.log"

function container_step_enable_traces
{
    # Turn on tracing of this script
    test -z "$DEBUG_TRACE" || set -x
}

function container_step_set_workdir_to_root
{
    cd /
}

function container_step_exec_whitelist_commands
{
    case "${ARGS[0]}" in
        /bin/install.sh|/bin/uninstall.sh|/bin/bash|bash)
            exec "${ARGS[@]}"
        ;;
    esac
}

function container_helper_clean_directories_print_out
{
    for i in /run/* /tmp/var/tmp/* /tmp/*; do
        echo "$i"
    done
}
export -f container_helper_clean_directories_print_out

function container_step_clean_directories
{
    for i in $( container_helper_clean_directories_print_out ); do
        # FIXME Fix this shellcheck hint when refactoring this
        #       function for unit tests
        # shellcheck disable=SC2166
        if [ "$i" == '/run/secrets' ] ; then
            :
        elif [ -L "$i" -o -f "$i" ] ; then
            rm -f "$i"
        else
            for j in "$i"/* ; do
                if [ "$j" != '/tmp/var/tmp' ] ; then
                    rm -rf "$j"
                fi
            done
        fi
    done
}

function container_helper_invoke_populate_volume_from_template
{
    local directory="$1"
    [ "${directory}" != "" ] || return 1
    # Modify the populate-volume-from-template program to tolerate
    # chmod/chown failure.  We do this "inline" so that we do not
    # write the root fs (which may be read-only).
    sed \
        's/\(\s*\(chown\|chmod\).*\)/\1 || ( echo "Failed to \2 $VOLUME" ; ls -ld "$VOLUME" )/' \
        /usr/local/bin/populate-volume-from-template \
        | /bin/sh -s "${directory}"
}

function container_step_populate_tmp
{
    container_helper_invoke_populate_volume_from_template "/tmp"
}

function container_step_workaround_1372562
{
    # Workaround 1373562
    mkdir -p "/run/lock"
}


function container_step_create_directories
{
    mkdir -p "/run/ipa" "/run/log" "${DATA}/var/log/journal"
}

function container_step_link_journal
{
    ln -s "${DATA}/var/log/journal" "/run/log/journal"
}

function container_helper_write_no_poweroff_conf
{
    local output_file="$1"
    echo -e "[Service]\nFailureAction=none" > "${output_file}"
}

# TODO Clean-up
# function container_helper_write_poweroff_conf
function container_helper_link_to_power_off
{
    local _symlink_path="$1"
    # echo -e "[Service]\nExecStartPost=/usr/bin/systemctl poweroff" > "${output_file}"
    local _target_path="/usr/lib/systemd/system/ipa-server-configure-first.service.d/service-success-poweroff.conf.template"
    ln -s "${_target_path}" "${_symlink_path}"
}

function container_step_do_check_terminate_await
{
    if [ "${ARGS[0]}" == 'no-exit' ] || utils_is_not_empty_str "${DEBUG_NO_EXIT}" ; then
        if [ "${ARGS[0]}" == 'no-exit' ] ; then
            tasks_helper_shift_args
        fi
        # Debugging:  Don't power off if IPA install/upgrade fails
        # Create service drop-in to override `FailureAction`
        for i in ipa-server-configure-first.service ipa-server-upgrade.service; do
            mkdir -p /run/systemd/system/$i.d
            container_helper_write_no_poweroff_conf "/run/systemd/system/$i.d/50-no-poweroff.conf"
        done
    elif [ "${ARGS[0]}" == 'exit-on-finished' ] ; then
        for i in ipa-server-configure-first.service ipa-server-upgrade.service; do
            mkdir -p /run/systemd/system/$i.d
            # We'd like to use SuccessAction=poweroff here but it's only
            # available in systemd 236.
            container_helper_link_to_power_off "/run/systemd/system/$i.d/50-success-poweroff.conf"
        done
        tasks_helper_shift_args
    fi
    return 0
}

function container_step_enable_tracing
{
    # Debugging:  Turn on tracing of ipa-server-configure-first script
    test -z "${DEBUG_TRACE}" || touch /run/ipa/debug-trace
}

function container_step_read_command
{
    if utils_is_not_empty_str "${ARGS[0]}" ; then
        case "${ARGS[0]}" in
            ipa-server-install)
                COMMAND="${ARGS[0]}"
                tasks_helper_shift_args
            ;;
            ipa-replica-install)
                COMMAND="${ARGS[0]}"
                tasks_helper_shift_args
            ;;
            -*)
                :
            ;;
            *)
            echo "Invocation error: command [${ARGS[0]}] not supported." >&2
            exit 8
        esac
    fi

    if utils_is_empty_str "${COMMAND}" ; then
        if utils_is_a_file "${DATA}/ipa-replica-install-options" ; then
            COMMAND="ipa-replica-install"
        else
            COMMAND="ipa-server-install"
        fi
    fi
}

function container_step_check_ipa_server_install_opts
{
    if utils_is_not_empty_str "${IPA_SERVER_INSTALL_OPTS}" && [ "${COMMAND}" != 'ipa-server-install' ] && [ "${COMMAND}" != 'ipa-replica-install' ] ; then
        echo "Invocation error: IPA_SERVER_INSTALL_OPTS should only be used with ipa-server-install or ipa-replica-install." >&2
        exit 7
    fi
}

function container_step_set_options_file_vars
{
    OPTIONS_FILE="/run/ipa/${COMMAND}-options"
    DATA_OPTIONS_FILE="${DATA}/${COMMAND}-options"
}

# TODO Clean-up
# function container_step_print_out_option_file_content
# {
#     if [ "${OPTIONS_FILE}" != "" ] && [ -e "${OPTIONS_FILE}" ]; then
#         tasks_helper_msg_info ">> OPTIONS_FILE content: ${OPTIONS_FILE}"
#         cat "${OPTIONS_FILE}"
#     fi
#
#     if [ "${DATA_OPTIONS_FILE}" != "" ] && [ -e "${DATA_OPTIONS_FILE}" ]; then
#         tasks_helper_msg_info ">> DATA_OPTIONS_FILE content: ${DATA_OPTIONS_FILE}"
#         cat "${DATA_OPTIONS_FILE}"
#     fi
# }

function container_step_fill_options_file
{
    touch "${OPTIONS_FILE}"
    chmod 600 "${OPTIONS_FILE}"
    for i in "${ARGS[@]}" ; do
        printf '%q\n' "$i" >> "${OPTIONS_FILE}"
    done
}

function container_helper_cat_options_file
{
    cat "${OPTIONS_FILE}"
}

function container_step_read_ipa_server_hostname_arg_from_options_file
{
    local _hostname_in_next
    _hostname_in_next=0
    for i in $( container_helper_cat_options_file ) ; do
        if [ ${_hostname_in_next} -eq 1 ] ; then
            IPA_SERVER_HOSTNAME="$i"
            break
        fi
        case "$i" in
            "--hostname" | "-h")
                _hostname_in_next=1
                ;;
            --hostname=*)
                IPA_SERVER_HOSTNAME="${i#--hostname=}"
                break
                ;;
        esac
    done
}

function container_helper_cat_stored_hostname
{
    cat "${DATA}/hostname"
}
export -f container_helper_cat_stored_hostname

function container_helper_exist_stored_hostname
{
    utils_is_a_file "${DATA}/hostname"
}

function container_helper_set_hosts_file
{
    local _hostname="$1"
    local _ipa_server_hostname="$2"
    [ "${_hostname}" != "" ] || return 1
    [ "${_ipa_server_hostname}" != "" ] || return 2
    cp /etc/hosts /etc/hosts.dist
    sed "s/${_hostname}/${_ipa_server_hostname} ${_ipa_server_hostname}. &/" /etc/hosts.dist > /etc/hosts
    rm -f /etc/hosts.dist
}

function container_helper_store_hostname
{
    local _hostname="$1"
    [ "${_hostname}" != "" ] || return 1
    printf "%s\n" "${_hostname}" > "${DATA}/hostname"
}

function container_helper_error_invoked_without_fqdn
{
    printf "Container invoked without fully-qualified hostname\n" >&2
    printf "   and without specifying hostname to use.\n" >&2
    printf "Consider using -h FQDN option to docker run.\n" >&2
    return 15
}

function container_step_process_hostname
{
	if container_helper_exist_stored_hostname ; then
		STORED_HOSTNAME="$( container_helper_cat_data_hostname )"
		if ! [ "${HOSTNAME}" == "${STORED_HOSTNAME}" ] ; then
			# Attempt to set hostname from within container, this
			# will pass if the container has SYS_ADMIN capability.
			if hostname "${STORED_HOSTNAME}" 2> /dev/null ; then
				HOSTNAME="$( hostname )"
				if [ "${HOSTNAME}" == "${STORED_HOSTNAME}" ] && ! [ "${IPA_SERVER_HOSTNAME}" == "${HOSTNAME}" ] ; then
					printf "%s\n" "Using stored hostname ${STORED_HOSTNAME}, ignoring ${IPA_SERVER_HOSTNAME}."
				fi
			fi
		fi
		IPA_SERVER_HOSTNAME="${STORED_HOSTNAME}"
	fi

	HOSTNAME_SHORT=${HOSTNAME%%.*}
	if [ "$HOSTNAME_SHORT" == "$HOSTNAME" ] ; then
		if utils_is_empty_str "${IPA_SERVER_HOSTNAME}" ; then
            container_helper_error_invoked_without_fqdn
            exit $?
		fi
		# Container is run without FQDN set, we try to "set" it in /etc/hosts
        container_helper_set_hosts_file "${HOSTNAME}" "${IPA_SERVER_HOSTNAME}"
		HOSTNAME="${IPA_SERVER_HOSTNAME}"
	fi

    if ! container_helper_exist_stored_hostname ; then
        container_helper_store_hostname "${HOSTNAME}"
    fi
}

function container_helper_create_machine_id
{
	# only triggers when /etc/machine-id is a symlink and not bind-mounted into
	# the container by a container runtime.
	if utils_is_a_symlink "/etc/machine-id" \
    && ! utils_is_a_file "${DATA}/etc/machine-id" ; then
        dbus-uuidgen --ensure=${DATA}/etc/machine-id
		chmod 444 "${DATA}/etc/machine-id"
	fi
}

function container_helper_exist_ca_cert
{
    utils_is_a_file "/etc/ipa/ca.crt"
}

function container_step_process_first_boot
{
    if ! container_helper_exist_ca_cert ; then
        if ! utils_is_a_file "${DATA}/ipa.csr" ; then
            # Do not refresh $DATA in the second stage of the external CA setup
            /usr/local/bin/populate-volume-from-template "${DATA}"
            container_helper_create_machine_id
        fi

        if [ -n "${PASSWORD}" ] ; then
            if [ "${COMMAND}" == 'ipa-server-install' ] ; then
                printf '%q\n' "--admin-password=${PASSWORD}" >> "${OPTIONS_FILE}"
                if ! grep -sq '^--ds-password' "${OPTIONS_FILE}" "${DATA_OPTIONS_FILE}" ; then
                    printf '%q\n' "--ds-password=${PASSWORD}" >> "${OPTIONS_FILE}"
                fi
            elif [ "${COMMAND}" == 'ipa-replica-install' ] ; then
                if grep -sq '^--principal' "${OPTIONS_FILE}" "${DATA_OPTIONS_FILE}" ; then
                    printf '%q\n' "--admin-password=${PASSWORD}" >> "${OPTIONS_FILE}"
                else
                    printf '%q\n' "--password=$PASSWORD" >> "${OPTIONS_FILE}"
                fi
            else
                echo "Warning: ignoring environment variable PASSWORD." >&2
            fi
        fi

        if [ -n "$IPA_SERVER_INSTALL_OPTS" ] ; then
            # FIXME Fix this shellcheck hint when refactoring this
            #       function for unit tests
            # shellcheck disable=SC2166
            if [ "$COMMAND" == 'ipa-server-install' -o "$COMMAND" = 'ipa-replica-install' ] ; then
                echo "$IPA_SERVER_INSTALL_OPTS" >> $OPTIONS_FILE
            else
                echo "Warning: ignoring environment variable IPA_SERVER_INSTALL_OPTS." >&2
            fi
        fi

        if [ -n "${DEBUG}" ] ; then
            echo "--debug" >> ${OPTIONS_FILE}
        fi
    fi
}

# Some commands can not be mocked because interfere
# with the testing framework, because of that this
# function exists.
function container_helper_print_data_volume_version
{
    cat "${DATA}/volume-version"
}
export -f container_helper_print_data_volume_version

# Some commands can not be mocked because interfere
# with the testing framework, because of that this
# function exists.
function container_helper_print_image_volume_version
{
    cat "/etc/volume-version"
}
export -f container_helper_print_image_volume_version

function container_step_upgrade_version
{
    # Check the volume-version of the bind-mounted volume, upgrade if it's
    # different from the one in this image.
    # The volume-upgrade file names are in format:
    #         ipa-volume-upgrade-$OLDVERSION-$NEWVERSION
    if utils_is_a_file "${DATA}/volume-version" ; then
        DATA_VERSION="$( container_helper_print_data_volume_version )"
        IMAGE_VERSION="$( container_helper_print_image_volume_version )"
        if ! [ "${DATA_VERSION}" == "${IMAGE_VERSION}" ] ; then
            if [ -x "/usr/sbin/ipa-volume-upgrade-${DATA_VERSION}-${IMAGE_VERSION}" ] ; then
                printf "%s\n" "Migrating ${DATA} data volume version ${DATA_VERSION} to ${IMAGE_VERSION}."
                if "/usr/sbin/ipa-volume-upgrade-${DATA_VERSION}-${IMAGE_VERSION}" ; then
                    container_helper_print_image_volume_version > "${DATA}/volume-version"
                else
                    printf "%s\n" "Migration of ${DATA} volume to version ${IMAGE_VERSION} failed."
                    exit 13
                fi
            fi
        fi
    fi
}

function container_step_volume_update
{
    if utils_is_a_file "${DATA}/build-id" ; then
        if ! cmp -s $DATA/build-id $DATA_TEMPLATE/build-id ; then
            echo "FreeIPA server is already configured but with different version, volume update."
            /usr/local/bin/populate-volume-from-template $DATA
            container_helper_create_machine_id
            # FIXME Fix this shellcheck hint when refactoring this
            #       function for unit tests
            # shellcheck disable=SC2162
            sha256sum -c /etc/volume-data-autoupdate 2> /dev/null | awk -F': ' '/OK$/ { print $1 }' \
                | while read f ; do
                    rm -f "$DATA/$f"
                    if [ -e "$DATA_TEMPLATE/$f" ] ; then
                        ( cd $DATA_TEMPLATE && tar cf - "./$f" ) | ( cd $DATA && tar xvf - )
                    fi
                done
            # FIXME Fix this shellcheck hint when refactoring this
            #       function for unit tests
            # shellcheck disable=SC2162,SC2002
            cat /etc/volume-data-list | while read i ; do
                if [ -e "${DATA_TEMPLATE}$i" ] && [ -e "$DATA$i" ] ; then
                    chown "--reference=${DATA_TEMPLATE}$i" "${DATA}$i" \
                        || ( echo "Failed to chown $VOLUME" ; ls -ld "$VOLUME" )
                    chmod "--reference=${DATA_TEMPLATE}$i" "${DATA}$i" \
                        || ( echo "Failed to chmod $VOLUME" ; ls -ld "$VOLUME" )
                fi
            done
            SYSTEMD_OPTS=--unit=ipa-server-upgrade.service
        fi
        if container_helper_exist_ca_cert ; then
            rm -f "${DATA}/etc/systemd/system/multi-user.target.wants/ipa-server-configure-first.service"
        fi
    fi
}

function container_step_print_out_timestamps_and_args
{
    printf "%s %s\n" "$(date)" "${ARGS[*]}" >> "${LOGFILE_IPA_SERVER_CONFIGURE_FIRST}"
}

function container_helper_print_out_log
{
    export LOGFILE_IPA_SERVER_CONFIGURE_FIRST LOGFILE_IPA_SERVER_RUN
    (
        trap '' SIGHUP
        tail --silent -n 0 -f --retry "${LOGFILE_IPA_SERVER_CONFIGURE_FIRST}" "${LOGFILE_IPA_SERVER_RUN}" 2> /dev/null < /dev/null &
    )
}

function container_step_do_show_log_if_enabled
{
    SHOW_LOG=${SHOW_LOG:-1}
    if [ "${SHOW_LOG}" == 1 ] ; then
        for i in "${LOGFILE_IPA_SERVER_CONFIGURE_FIRST}" "${LOGFILE_IPA_SERVER_RUN}" ; do
            if ! utils_is_a_file "$i" ; then
                touch $i
            fi
        done
        container_helper_print_out_log
    fi
}

function container_helper_write_ipa_server_ip_to_file
{
    local _ipa_server_ip="$1"
    local _output="$2"
    [ "${_ipa_server_ip}" != "" ] || return 1
    [ "${_output}" != "" ] || return 2
    printf "%s\n" "${_ipa_server_ip}" > "${_output}"
}

function container_step_save_ipa_server_ip_if_provided
{
    if utils_is_not_empty_str "${IPA_SERVER_IP}" ; then
        # TODO Clean-up
        # printf "%s\n" "${IPA_SERVER_IP}" > /run/ipa/ipa-server-ip
        container_helper_write_ipa_server_ip_to_file "${IPA_SERVER_IP}" "/run/ipa/ipa-server-ip"
    fi
}

# TODO Clean-up this step
# function container_step_print_out_env_if_debug
# {
#     if [ "${DEBUG_TRACE}" != "" ]; then
#         env
#     fi
# }

function container_step_exec_init
{
    # exec /usr/sbin/init --show-status=false ${SYSTEMD_OPTS}
    exec /usr/sbin/init --show-status=true ${SYSTEMD_OPTS}

    exit 10
}

CONTAINER_LIST_TASKS=()

# +container:begin-list
CONTAINER_LIST_TASKS+=("container_step_enable_traces")
CONTAINER_LIST_TASKS+=("container_step_set_workdir_to_root")
CONTAINER_LIST_TASKS+=("container_step_exec_whitelist_commands")
CONTAINER_LIST_TASKS+=("container_step_clean_directories")
CONTAINER_LIST_TASKS+=("container_step_populate_tmp")
CONTAINER_LIST_TASKS+=("container_step_create_directories")
CONTAINER_LIST_TASKS+=("container_step_link_journal")
CONTAINER_LIST_TASKS+=("container_step_do_check_terminate_await")
CONTAINER_LIST_TASKS+=("container_step_enable_tracing")
CONTAINER_LIST_TASKS+=("container_step_read_command")
CONTAINER_LIST_TASKS+=("container_step_check_ipa_server_install_opts")
CONTAINER_LIST_TASKS+=("container_step_set_options_file_vars")
CONTAINER_LIST_TASKS+=("container_step_fill_options_file")
CONTAINER_LIST_TASKS+=("container_step_read_ipa_server_hostname_arg_from_options_file")
CONTAINER_LIST_TASKS+=("container_step_process_hostname")
CONTAINER_LIST_TASKS+=("container_step_process_first_boot")
CONTAINER_LIST_TASKS+=("container_step_upgrade_version")
CONTAINER_LIST_TASKS+=("container_step_volume_update")
CONTAINER_LIST_TASKS+=("container_step_do_show_log_if_enabled")
CONTAINER_LIST_TASKS+=("container_step_save_ipa_server_ip_if_provided")
# CONTAINER_LIST_TASKS+=("container_step_print_out_env_if_debug")
CONTAINER_LIST_TASKS+=("container_step_exec_init")
# +container:end-list

tasks_helper_add_tasks "${CONTAINER_LIST_TASKS[@]}"
