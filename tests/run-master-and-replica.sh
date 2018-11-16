#!/bin/bash

set -e
set -x

IMAGE="$1"

function run_ipa_container() {
	set +x
	N="$1" ; shift
	set -e
	date
	VOLUME=/tmp/freeipa-test-$$/data
	HOSTNAME=ipa.example.test
	if [ "$N" == "freeipa-replica" ] ; then
		HOSTNAME=replica.example.test
		VOLUME=/tmp/freeipa-test-$$/data-replica
	fi
	mkdir -p $VOLUME
	(
	set -x
	docker run -d --name "$N" -h $HOSTNAME \
		--sysctl net.ipv6.conf.all.disable_ipv6=0 \
		--tmpfs /run --tmpfs /tmp -v /dev/urandom:/dev/random:ro -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
		-v $VOLUME:/data:Z $DOCKER_RUN_OPTS \
		-e PASSWORD=Secret123 "$IMAGE" "$@"
	)
	docker logs -f "$N" &
	while true ; do
		sleep 10
		if ! docker exec "$N" systemctl is-system-running 2> /dev/null | grep -Eq 'starting|initializing' ; then
			break
		fi
	done
	date
	EXIT_STATUS=$( docker inspect "$N" --format='{{.State.ExitCode}}' )
	if [ "$EXIT_STATUS" -ne 0 ] ; then
		exit "$EXIT_STATUS"
	fi
	if docker diff "$N" | tee /dev/stderr | grep -Evf tests/docker-diff-ipa.out | grep . ; then
		exit 1
	fi
}

# Initial setup of the FreeIPA server
run_ipa_container freeipa-master exit-on-finished -U -r EXAMPLE.TEST --setup-dns --no-forwarders --no-ntp $ca

if [ -n "$ca" ] ; then
	docker rm -f freeipa-master
	date
	sudo tests/generate-external-ca.sh /tmp/freeipa-test-$$/data
	# For external CA, provide the certificate for the second stage
	run_ipa_container freeipa-master exit-on-finished -U -r EXAMPLE.TEST --setup-dns --no-forwarders --no-ntp \
		--external-cert-file=/data/ipa.crt --external-cert-file=/data/ca.crt
fi

docker rm -f freeipa-master
# Start the already-setup master server
run_ipa_container freeipa-master exit-on-finished

docker rm -f freeipa-master
# Force "upgrade" path by simulating image change
uuidgen | sudo tee /tmp/freeipa-test-$$/data/build-id
run_ipa_container freeipa-master

if [ "$replica" = 'none' ] ; then
	echo OK $0.
	exit
fi

# Setup replica
MASTER_IP=$( docker inspect --format '{{ .NetworkSettings.IPAddress }}' freeipa-master )
DOCKER_RUN_OPTS="--link freeipa-master:ipa.example.test --dns=$MASTER_IP"
run_ipa_container freeipa-replica ipa-replica-install -U --skip-conncheck --principal admin --setup-ca --no-ntp
date
if docker diff freeipa-master | tee /dev/stderr | grep -Evf tests/docker-diff-ipa.out | grep . ; then
	exit 1
fi
echo OK $0.
