#!/bin/bash

# All this infrastructure is based on freeipa-container work.
#
# This set of scripts are only an intent to refactor in a way the
# init script can be decoupled and the maintenance for related
# repositories could be more smooth and better managed.
#
# Knowledges to freeipa-container collaborators

INIT_DIR=/usr/local/share/ipa-container

source "${INIT_DIR}/includes.inc.sh"

tasks_execute "$@"
