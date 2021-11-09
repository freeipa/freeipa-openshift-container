#!/bin/bash

# All this infrastructure is based on freeipa-container work.
#
# This set of scripts are only an intent to refactor in a way the
# init script can be decoupled and the maintenance for related
# repositories could be more smooth and better managed.
#
# Knowledges to freeipa-container collaborators

INIT_DIR=/usr/local/share/ipa-container

set -e

# shellcheck disable=SC1091
source "${INIT_DIR}/includes.inc.sh"

# FIXME Remove line when debug finish
tasks_helper_msg_info "task list:" "$(tasks_helper_list)"

# set -xv

tasks_helper_execute
