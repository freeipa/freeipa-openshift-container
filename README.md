# freeipa Openshift workload

[![Dockerfile](https://github.com/avisiedo/freeipa-openshift-container-alternative/actions/workflows/hadolint.yaml/badge.svg)](https://github.com/avisiedo/freeipa-container-atlernative/actions/workflows/hadolint.yaml)

This repository store the container definition that is used for provisioning
Freeipa in Openshift.

freeipa-container work quite well in containers, but there are some caveats to
be solved for Openshift; this repository update some hacks using a modified
init-data script which implements the necessary for making the container works
into Openshift.

Synced to init-data at 73940d4 git state.

## Getting started

1) Fill up the file `private.mk` with some minimal variables which will avoid to
pass information through the command line. The content could be something like
the below:

```raw
IPA_ADMIN_PASSWORD = Secret123
IPA_DM_PASSWORD = DMSecret123
IMG_BASE = quay.io/scope-name
```

> The variable `PASSWORD` still set both password when the above ones are
> not specified; but it is recommended to use `IPA_ADMIN_PASSWORD` and
> `IPA_DM_PASSWORD`.

- **IPA_ADMIN_PASSWORD** is the administrator password.
- **IPA_DM_PASSWORD** is the directory manager password.
- **IMG_BASE** is the base name used to compose the container image name.


2) log into container registry with your account (e.g. ``podman login quay.io``)
3) optionally ``export KUBECONFIG="/path/to/kubeconfig"`` if you wish to use a
  custom configuration (e.g. cluster-bot).
4) log into OpenShift cluster: ``oc login -u kubeadmin``
5) make container repositories be accessible to OpenShift. Depending on your
  configuration, new Quay repositories may be private.


6) Create container and push it to container registry

```shell
make container-build container-push
```

> Where **scope** is the name of the account or organization where you will
> publish the image. It is required to be defined to avoid that by mistake
> it could be overwritten any image into the **freeipa** organization.

7) Create project and deploy app

```shell
oc new-project freeipa
make app-create
```

To remove the created objects just:

```shell
make app-delete
```
