#!/bin/bash

# It is assumed tasks.inc.sh is included

DATA=/data
DATA_TEMPLATE=/data-template
COMMAND=
OPTIONS_FILE=
DATA_OPTIONS_FILE=
IPA_SERVER_HOSTNAME="${IPA_SERVER_HOSTNAME}"
HOSTNAME="${HOSTNAME}"
IPA_SERVER_IP="${IPA_SERVER_IP}"
SYSTEMD_OPTS="${SYSTEMD_OPTS}"

function container_step_enable_traces
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

function container_step_set_workdir_root
{
    cd /
}

function container_step_exec_whitelist_commands
{
    case "${ARGS[1]}" in
        /bin/install.sh|/bin/uninstall.sh|/bin/bash|bash)
            exec "${ARGS[@]}"
        ;;
    esac
}

function container_step_clean_directories
{
    for i in /run/* /tmp/var/tmp/* /tmp/* ; do
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

function container_step_populate_volume_from_template
{
    /usr/local/bin/populate-volume-from-template "/tmp"
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

function container_step_do_check_terminate_await
{
    if [ "${ARGS[0]}" == 'no-exit' -o -n "${DEBUG_NO_EXIT}" ] ; then
        if [ "${ARGS[0]}" == 'no-exit' ] ; then
            tasks_helper_shift_args
        fi
        # Debugging:  Don't power off if IPA install/upgrade fails
        # Create service drop-in to override `FailureAction`
        for i in ipa-server-configure-first.service ipa-server-upgrade.service; do
            mkdir -p /run/systemd/system/$i.d
            echo -e "[Service]\nFailureAction=none" > /run/systemd/system/$i.d/50-no-poweroff.conf
        done
    elif [ "${ARGS[0]}" == 'exit-on-finished' ] ; then
        for i in ipa-server-configure-first.service ipa-server-upgrade.service; do
            mkdir -p /run/systemd/system/$i.d
            # We'd like to use SuccessAction=poweroff here but it's only
            # available in systemd 236.
            echo -e "[Service]\nExecStartPost=/usr/bin/systemctl poweroff" > /run/systemd/system/$i.d/50-success-poweroff.conf
        done
        tasks_helper_shift_args
    fi
}

function container_step_enable_tracing
{
    # Debugging:  Turn on tracing of ipa-server-configure-first script
    test -z "${DEBUG_TRACE}" || touch /run/ipa/debug-trace
}

function container_step_read_command
{
    if [ -n "${ARGS[0]}" ] ; then
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

    if [ -z "${COMMAND}" ] ; then
        if [ -f $DATA/ipa-replica-install-options ] ; then
            COMMAND=ipa-replica-install
        else
            COMMAND=ipa-server-install
        fi
    fi
}

function container_step_check_ipa_server_install_opts
{
    if [ -n "${IPA_SERVER_INSTALL_OPTS}" ] && [ "${COMMAND}" != 'ipa-server-install' ] && [ "${COMMAND}" != 'ipa-replica-install' ] ; then
        echo "Invocation error: IPA_SERVER_INSTALL_OPTS should only be used with ipa-server-install or ipa-replica-install." >&2
        exit 7
    fi
}

function container_step_set_options_file_vars
{
    OPTIONS_FILE="/run/ipa/${COMMAND}-options"
    DATA_OPTIONS_FILE="${DATA}/${COMMAND}-options"
}

function container_step_print_out_option_file_content
{
    if [ "${OPTIONS_FILE}" != "" ] && [ -e "${OPTIONS_FILE}" ]; then
        tasks_helper_msg_info ">> OPTIONS_FILE content: ${OPTIONS_FILE}"
        cat "${OPTIONS_FILE}"
    fi

    if [ "${DATA_OPTIONS_FILE}" != "" ] && [ -e "${DATA_OPTIONS_FILE}" ]; then
        tasks_helper_msg_info ">> DATA_OPTIONS_FILE content: ${DATA_OPTIONS_FILE}"
        cat "${DATA_OPTIONS_FILE}"
    fi
}

function container_step_fill_options_file
{
    touch "${OPTIONS_FILE}"
    chmod 660 "${OPTIONS_FILE}"
    for i in "${ARGS[@]}" ; do
        printf '%q\n' "$i" >> "${OPTIONS_FILE}"
    done
}

function container_step_read_ipa_server_hostname_arg_from_options_file
{
    local _hostname_in_next
    _hostname_in_next=0
    for i in $( cat "${OPTIONS_FILE}" ) ; do
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

function container_step_process_hostname
{
	if [ -f "${DATA}/hostname" ] ; then
		STORED_HOSTNAME="$( cat "${DATA}/hostname" )"
		if ! [ "${HOSTNAME}" == "${STORED_HOSTNAME}" ] ; then
			# Attempt to set hostname from within container, this
			# will pass if the container has SYS_ADMIN capability.
			if hostname "${STORED_HOSTNAME}" 2> /dev/null ; then
				HOSTNAME=$( hostname )
				if [ "${HOSTNAME}" == "${STORED_HOSTNAME}" ] && ! [ "${IPA_SERVER_HOSTNAME}" == "${HOSTNAME}" ] ; then
					echo "Using stored hostname ${STORED_HOSTNAME}, ignoring ${IPA_SERVER_HOSTNAME}."
				fi
			fi
		fi
		IPA_SERVER_HOSTNAME=$STORED_HOSTNAME
	fi

	HOSTNAME_SHORT=${HOSTNAME%%.*}
	if [ "$HOSTNAME_SHORT" == "$HOSTNAME" ] ; then
		if [ -z "$IPA_SERVER_HOSTNAME" ] ; then
			echo "Container invoked without fully-qualified hostname" >&2
			echo "   and without specifying hostname to use." >&2
			echo "Consider using -h FQDN option to docker run." >&2
			exit 15
		fi
		# Container is run without FQDN set, we try to "set" it in /etc/hosts
		cp /etc/hosts /etc/hosts.dist
		sed "s/$HOSTNAME/$IPA_SERVER_HOSTNAME $IPA_SERVER_HOSTNAME. &/" /etc/hosts.dist > /etc/hosts
		rm -f /etc/hosts.dist
		HOSTNAME=$IPA_SERVER_HOSTNAME
	fi

    if ! [ -f "$DATA/hostname" ] ; then
        echo "$HOSTNAME" > "$DATA/hostname"
    fi
}

function container_helper_create_machine_id
{
	# only triggers when /etc/machine-id is a symlink and not bind-mounted into
	# the container by a container runtime.
	if [ -L /etc/machine-id ] && [ ! -f $DATA/etc/machine-id ] ; then
		# https://systemd.io/CONTAINER_INTERFACE/
		# shellcheck disable=SC2154
		if [ "${container_uuid}" != "" ]; then
			echo "${container_uuid}" > "${DATA}/etc/machine-id"
		else
			dbus-uuidgen --ensure=$DATA/etc/machine-id
		fi
		chmod 444 $DATA/etc/machine-id
	fi
}

function container_step_process_first_boot
{
    if ! [ -f /etc/ipa/ca.crt ] ; then
        if ! [ -f $DATA/ipa.csr ] ; then
            # Do not refresh $DATA in the second stage of the external CA setup
            /usr/local/bin/populate-volume-from-template $DATA
            container_helper_create_machine_id
        fi

        if [ -n "$PASSWORD" ] ; then
            if [ "$COMMAND" == 'ipa-server-install' ] ; then
                printf '%q\n' "--admin-password=$PASSWORD" >> ${OPTIONS_FILE}
                if ! grep -sq '^--ds-password' $OPTIONS_FILE $DATA_OPTIONS_FILE ; then
                    printf '%q\n' "--ds-password=$PASSWORD" >> $OPTIONS_FILE
                fi
            elif [ "$COMMAND" == 'ipa-replica-install' ] ; then
                if grep -sq '^--principal' $OPTIONS_FILE $DATA_OPTIONS_FILE ; then
                    printf '%q\n' "--admin-password=$PASSWORD" >> $OPTIONS_FILE
                else
                    printf '%q\n' "--password=$PASSWORD" >> $OPTIONS_FILE
                fi
            else
                echo "Warning: ignoring environment variable PASSWORD." >&2
            fi
        fi

        if [ -n "$IPA_SERVER_INSTALL_OPTS" ] ; then
            if [ "$COMMAND" == 'ipa-server-install' -o "$COMMAND" = 'ipa-replica-install' ] ; then
                echo "$IPA_SERVER_INSTALL_OPTS" >> $OPTIONS_FILE
            else
                echo "Warning: ignoring environment variable IPA_SERVER_INSTALL_OPTS." >&2
            fi
        fi

        if [ -n "$DEBUG" ] ; then
            echo "--debug" >> $OPTIONS_FILE
        fi
    fi
}

function container_step_upgrade_version
{
    # Check the volume-version of the bind-mounted volume, upgrade if it's
    # different from the one in this image.
    # The volume-upgrade file names are in format:
    #         ipa-volume-upgrade-$OLDVERSION-$NEWVERSION
    if [ -f "$DATA/volume-version" ] ; then
        DATA_VERSION=$(cat $DATA/volume-version)
        IMAGE_VERSION=$(cat /etc/volume-version)
        if ! [ "$DATA_VERSION" == "$IMAGE_VERSION" ] ; then
            if [ -x /usr/sbin/ipa-volume-upgrade-$DATA_VERSION-$IMAGE_VERSION ] ; then
                echo "Migrating $DATA data volume version $DATA_VERSION to $IMAGE_VERSION."
                if /usr/sbin/ipa-volume-upgrade-$DATA_VERSION-$IMAGE_VERSION ; then
                    cat /etc/volume-version > $DATA/volume-version
                else
                    echo "Migration of $DATA volume to version $IMAGE_VERSION failed."
                    exit 13
                fi
            fi
        fi
    fi
    if [ -f "$DATA/build-id" ] ; then
        if ! cmp -s $DATA/build-id $DATA_TEMPLATE/build-id ; then
            echo "FreeIPA server is already configured but with different version, volume update."
            /usr/local/bin/populate-volume-from-template $DATA
            container_helper_create_machine_id
            sha256sum -c /etc/volume-data-autoupdate 2> /dev/null | awk -F': ' '/OK$/ { print $1 }' \
                | while read f ; do
                    rm -f "$DATA/$f"
                    if [ -e "$DATA_TEMPLATE/$f" ] ; then
                        ( cd $DATA_TEMPLATE && tar cf - "./$f" ) | ( cd $DATA && tar xvf - )
                    fi
                done
            cat /etc/volume-data-list | while read i ; do
                if [ -e "${DATA_TEMPLATE}$i" ] && [ -e "$DATA$i" ] ; then
                    chown "--reference=${DATA_TEMPLATE}$i" "${DATA}$i"
                    chmod "--reference=${DATA_TEMPLATE}$i" "${DATA}$i"
                fi
            done
            SYSTEMD_OPTS=--unit=ipa-server-upgrade.service
        fi
        if [ -f /etc/ipa/ca.crt ] ; then
            rm -f "${DATA}/etc/systemd/system/multi-user.target.wants/ipa-server-configure-first.service"
        fi
    fi
}

function container_step_print_out_timestamps_and_args
{
    echo "$(date) ${ARGS[0]} ${ARGS[*]}" >> /var/log/ipa-server-configure-first.log
}

function container_step_do_show_log_if_enabled
{
    SHOW_LOG=${SHOW_LOG:-1}
    if [ "${SHOW_LOG}" == 1 ] ; then
        for i in /var/log/ipa-server-configure-first.log /var/log/ipa-server-run.log ; do
            if ! [ -f $i ] ; then
                touch $i
            fi
        done
        (
        trap '' SIGHUP
        tail --silent -n 0 -f --retry /var/log/ipa-server-configure-first.log /var/log/ipa-server-run.log 2> /dev/null < /dev/null &
        )
    fi

    if [ -n "${IPA_SERVER_IP}" ] ; then
        echo "${IPA_SERVER_IP}" > /run/ipa/ipa-server-ip
    fi
}

function container_step_print_out_env_if_debug
{
    if [ "${DEBUG_TRACE}" != "" ]; then
        env
    fi
}

function container_step_exec_init
{
    # exec /usr/sbin/init --show-status=false $SYSTEMD_OPTS
    exec /usr/sbin/init --show-status=true ${SYSTEMD_OPTS}

    exit 10
}

CONTAINER_LIST_TASKS=()

# +container:begin-list
CONTAINER_LIST_TASKS+=("container_step_enable_traces")
CONTAINER_LIST_TASKS+=("container_step_set_workdir_root")
CONTAINER_LIST_TASKS+=("container_step_exec_whitelist_commands")
CONTAINER_LIST_TASKS+=("container_step_clean_directories")
CONTAINER_LIST_TASKS+=("container_step_populate_volume_from_template")
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
CONTAINER_LIST_TASKS+=("container_step_do_show_log_if_enabled")
CONTAINER_LIST_TASKS+=("container_step_print_out_env_if_debug")
CONTAINER_LIST_TASKS+=("container_step_exec_init")
# +container:end-list

tasks_helper_add_tasks "${CONTAINER_LIST_TASKS[@]}"
