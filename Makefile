include private.mk

# This makefile make life easier for playing with the different
# proof of concepts.

# Customizable cluster domain for deploying wherever we want
CLUSTER_DOMAIN ?= $(shell kubectl get dnses.config.openshift.io/cluster -o json | jq -r '.spec.baseDomain' )
REALM ?= APPS.$(shell echo $(CLUSTER_DOMAIN) | tr  '[:lower:]' '[:upper:]')
NAMESPACE ?= $(shell oc project --short=true 2>/dev/null)
IPA_SERVER_HOSTNAME ?= $(NAMESPACE).apps.$(CLUSTER_DOMAIN)
TIMESTAMP ?= $(shell date +%Y%m%d%H%M%S)
CA_SUBJECT := --ca-subject=CN=freeipa-$(TIMESTAMP), O=$(REALM)

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
	$(DOCKER) build -t $(IMG) -f Dockerfile .

# Push the container image to the container registry
.PHONY: container-push
container-push: .check-docker-image-not-empty .FORCE
	$(DOCKER) push $(IMG)

# Remove container image from the local storage
.PHONY: container-remove
container-remove: .check-docker-image-not-empty .FORCE
	$(DOCKER) image rm $(IMG)

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
ifeq (,$(PASSWORD))
	@echo "ERROR: PASSWORD can not be empty"; exit 2
endif

.PHONY: .generate-secret
.generate-secret: deploy/user/admin-pass.txt .FORCE
	@{ \
		echo "PASSWORD=$(PASSWORD)"; \
	} > deploy/user/admin-pass.txt

.PHONY: .generate-config
.generate-config: deploy/user/config.txt .FORCE
	@{ \
		echo "DEBUG_TRACE=" ; \
  		echo "CLUSTER_DOMAIN=$(CLUSTER_DOMAIN)" ; \
  		echo "IPA_SERVER_HOSTNAME=$(IPA_SERVER_HOSTNAME)" ; \
		echo "CA_SUBJECT"=$(CA_SUBJECT) ; \
	} > deploy/user/config.txt

# Deploy the application
.PHONY: app-create
app-create: .check-not-empty-password .check-cluster-domain-not-empty .check-docker-image-not-empty .check-logged-in-openshift app-validate .generate-secret .generate-config .FORCE
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
	@kustomize build deploy/admin
	@echo "---"
	@kustomize build deploy/user

.PHONY: app-open-console
app-open-console:
	$(OPEN) https://$(NAMESPACE).apps.$(CLUSTER_DOMAIN)
