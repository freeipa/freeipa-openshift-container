include private.mk

# Read the parent image that is used for building the container image
PARENT_IMG ?= $(shell source ci/config/env; echo $${PARENT_IMG})

# This makefile make life easier for playing with the different
# proof of concepts.

# Customizable cluster domain for deploying wherever we want
# CLUSTER_DOMAIN ?= $(shell kubectl get dnses.config.openshift.io/cluster -o json | jq -r '.spec.baseDomain')
CLUSTER_DOMAIN_CMD = kubectl get dnses.config.openshift.io/cluster -o json | jq -r '.spec.baseDomain'
CLUSTER_DOMAIN ?= $(shell $(CLUSTER_DOMAIN_CMD))
# REALM ?= APPS.$(shell echo $(CLUSTER_DOMAIN) | tr  '[:lower:]' '[:upper:]')
REALM_CMD = echo "APPS.$(shell echo $(shell $(CLUSTER_DOMAIN_CMD)) | tr  '[:lower:]' '[:upper:]')"
REALM ?= $(shell $(REALM_CMD))
# NAMESPACE ?= $(shell oc project --short=true 2>/dev/null)
NAMESPACE_CMD = oc project --short=true 2>/dev/null
NAMESPACE ?= $(shell $(NAMESPACE_CMD))
# IPA_SERVER_HOSTNAME ?= $(NAMESPACE).apps.$(CLUSTER_DOMAIN)
IPA_SERVER_HOSTNAME_CMD = echo "$(NAMESPACE).apps.$(CLUSTER_DOMAIN)"
IPA_SERVER_HOSTNAME ?= $(shell $(IPA_SERVER_HOSTNAME_CMD))
TIMESTAMP ?= $(shell date +%Y%m%d%H%M%S)
CA_SUBJECT := CN=freeipa-$(TIMESTAMP), O=$(REALM)

TESTS_LIST ?= $(wildcard test/unit/*.bats)

# Set the container runtime interface
ifneq (,$(shell bash -c "command -v podman 2>/dev/null"))
DOCKER ?= podman
else
ifneq (,$(shell bash -c "command -v docker 2>/dev/null"))
DOCKER ?= docker
else
ifeq (,$(DOCKER))
$(error DOCKER is not set)
endif
endif
endif

# linux
ifneq (,$(shell bash -c "command -v xdg-open" 2>/dev/null))
OPEN := xdg-open
else
# macos
	ifneq (,$(shell bash -c "command -v open" 2>/dev/null))
OPEN := open
	else
OPEN := echo Open
	endif
endif

# Change IMG_BASE on your pipeline settings to point to your upstream
ifeq (,$(IMG_BASE))
$(error IMG_BASE is empty; export IMG_BASE=quay.io/namespace)
endif
IMG_TAG ?= dev-$(shell git rev-parse --short HEAD)
IMG ?= $(IMG_BASE)/freeipa-openshift-container:$(IMG_TAG)
QUAY_EXPIRATION ?= 1d
CONTAINER_BUILD_FLAGS ?=

default: help

.PHONY: .FORCE
.FORCE:

.PHONY: help
help: .FORCE
	@cat HELP

.PHONY: dump-vars
dump-vars:
	@echo CLUSTER_DOMAIN=$(CLUSTER_DOMAIN)
	@echo REALM=$(REALM)
	@echo TIMESTAMP=$(TIMESTAMP)
	@echo DOCKER=$(DOCKER)
	@echo NAMESPACE=$(NAMESPACE)
	@echo IMG_BASE=$(IMG_BASE)
	@echo IMG=$(IMG)

# Check IMG is not empty
.PHONY: .check-docker-image-not-empty
.check-docker-image-not-empty: .FORCE
ifeq (,$(IMG))
	@echo "'IMG' must be defined. Eg: 'export IMG=quay.io/myusername/freeipa-server:latest'"
	@exit 1
endif

# Build the container image
.PHONY: container-build
container-build: .check-docker-image-not-empty Dockerfile
	@echo "PARENT_IMG=$(PARENT_IMG)"
	$(DOCKER) build -t $(IMG) \
		--build-arg PARENT_IMG=$(PARENT_IMG) \
		--build-arg QUAY_EXPIRATION=$(QUAY_EXPIRATION) \
		$(CONTAINER_BUILD_FLAGS) \
		-f Dockerfile .

# Push the container image to the container registry
.PHONY: container-push
container-push: .check-docker-image-not-empty .FORCE
	$(DOCKER) push $(IMG)

# Remove container image from the local storage
.PHONY: container-remove
container-remove: .check-docker-image-not-empty .FORCE
	$(DOCKER) image rm $(IMG)

.PHONY: container-shell
container-shell:
	$(DOCKER) run -it --entrypoint "" $(IMG) /bin/bash

PORTS ?= -p 8053:53/udp -p 8053:53 -p 8443:443 -p 8389:389 -p 8636:636 -p 8088:88 -p 8464:464 -p 8088:88/udp -p 8464:464/udp
.PHONY: container-run
container-run: .check-not-empty-password
	$(DOCKER) volume exists freeipa-data || $(DOCKER) volume create freeipa-data
	$(DOCKER) run -it -d --cap-add FSETID -v "freeipa-data:/data:z" --name freeipa-server-container --hostname ipa.example.test $(PORTS) $(IMG) no-exit ipa-server-install -U -r EXAMPLE.TEST --hostname=ipa.example.test --ds-password=$(IPA_DM_PASSWORD) --admin-password=$(IPA_ADMIN_PASSWORD) --no-ntp --no-sshd --no-ssh

.PHONY: container-logs
container-logs:
	$(DOCKER) logs -f freeipa-server-container | less

.PHONY: container-stop
container-stop:
	-$(DOCKER) container stop freeipa-server-container
	-$(DOCKER) container rm freeipa-server-container

.PHONY: container-clean
container-clean: container-stop
	$(DOCKER) volume rm freeipa-data

# Validate kubernetes object for the app
.PHONY: app-validate
app-validate: .check-logged-in-openshift .validate-admin .validate-user .FORCE

.validate-admin:
	kustomize build deploy/admin | oc create -f - --dry-run=client --validate=true
.validate-user:
	kustomize build deploy/user | oc create -f - --dry-run=client --validate=true

# .PHONY: container-deploy
# container-deploy:
# 	@echo oc new-app --docker-image $(IMG) --env PASSWORD=$(PASSWORD) --env REALM=$(REALM) --env IPA_SERVER_HOSTNAME=$(IPA_SERVER_HOSTNAME)

JOB_SPEC ?= avisiedo/freeipa-openshift-container-alternative
.PHONY: ci-operator
ci-operator:
	# ci-operator --config .ci-operator.yaml --git-ref avisiedo/freeipa-openshift-container-alternative@master
	JOB_SPEC="$(JOB_SPEC)" ci-operator --config .ci-operator.yaml


# Check that cluster domain is not empty
.PHONY: .check-cluster-domain-not-empty
.check-cluster-domain-not-empty: .FORCE
ifeq (,$(CLUSTER_DOMAIN))
	@echo "'CLUSTER_DOMAIN' must be specified; Try 'CLUSTER_DOMAIN=my.cluster.domain.com make ...'"
	@exit 1
endif

# Check logged in OpenShift cluster
.PHONY: .check-logged-in-openshift
.check-logged-in-openshift: .FORCE
ifeq (,$(shell oc whoami 2>/dev/null))
	@echo "ERROR: You must be logged in OpenShift cluster. Try 'oc login https://mycluster:6443' matching your cluster API endpoint"
	@exit 1
endif

# Check not empty password
.PHONY: .check-not-empty-password
.check-not-empty-password: .FORCE
ifeq (,$(IPA_ADMIN_PASSWORD))
	@echo "ERROR: IPA_ADMIN_PASSWORD can not be empty"; exit 2
endif
ifeq (,$(IPA_DM_PASSWORD))
	@echo "ERROR: IPA_DM_PASSWORD can not be empty"; exit 2
endif

.PHONY: .generate-secret
.generate-secret: .FORCE
	@{ \
		echo "IPA_ADMIN_PASSWORD=$(IPA_ADMIN_PASSWORD)"; \
		echo "IPA_DM_PASSWORD=$(IPA_DM_PASSWORD)"; \
	} > deploy/user/admin-pass.txt

.PHONY: .generate-config
.generate-config: .FORCE
	@{ \
		echo "DEBUG_TRACE=$(DEBUG_TRACE)" ; \
  		echo "CLUSTER_DOMAIN=$(CLUSTER_DOMAIN)" ; \
  		echo "IPA_SERVER_HOSTNAME=$(IPA_SERVER_HOSTNAME)" ; \
		echo "CA_SUBJECT=$(CA_SUBJECT)" ; \
		echo "REALM=$(REALM)" ; \
	} > deploy/user/config.txt

# Deploy the application
.PHONY: app-create
app-create: .check-not-empty-password .check-cluster-domain-not-empty .check-docker-image-not-empty .check-logged-in-openshift .generate-secret .generate-config app-validate .FORCE
	cd deploy/user; kustomize edit set image workload=$(IMG)
	kustomize build deploy/admin | oc create -f -
	kustomize build deploy/user | oc create -f - --as freeipa

# Delete the application from the cluster
.PHONY: app-delete
app-delete: .check-logged-in-openshift .FORCE
	-kustomize build deploy/user | oc delete -f - --as freeipa
	-kustomize build deploy/admin | oc delete -f -

.PHONY: app-print-out
app-print-out: .generate-secret .generate-config .FORCE
	@cd deploy/user; kustomize edit set image workload=$(IMG)
	@kustomize build deploy/admin
	@echo "---"
	@kustomize build deploy/user

.PHONY: app-open-console
app-open-console:
	$(OPEN) https://$(NAMESPACE).apps.$(CLUSTER_DOMAIN)

.PHONY: test
test: install-test-deps test-unit test-e2e

.PHONY: test-unit
test-unit:
	./test/libs/bats/bin/bats $(TESTS_LIST)

.PHONY: test-e2e
test-e2e: .venv
	source .venv/bin/activate; ansible-playbook ./test/e2e/run-tests.yaml 

.PHONY: install-test-deps
install-test-deps: .venv

.venv:
	python3 -m venv --copies .venv
	source .venv/bin/activate; pip install --upgrade pip
	source .venv/bin/activate ; \
	  pip install --requirement test/e2e/requirements.txt ; \
	  ansible-galaxy collection install containers.podman
