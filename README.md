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

## Installing and using the template

> Known bug:The template can be instantiated from the cli with 'oc' but
> it can not be instantiated from OpenShift Console. The pod is not created.

An Openshift template is provided that let you deploy the current workload state
by using some parameters; this template is using ephemeral storage which means
that the information is lost between pod restarts and with new template instances,
so keep it in mind when using it.

It requires to previously create the rbac objects at `deploy/admin` directory by:

```shell
kustomize build deploy/admin | oc create -f -
```

Afterward you can just do the below for installing the template:

```shell
# You could need to do 'export IMG_BASE=quay.io/scope-name'
# or add the variable to the 'private.mk' file
make template-create
```

And now you can use the template from the Openshift console, or from the command line
by using `oc new-app ...` command.

The Makefile provide the rules `template-new-app` and `template-rm-app` for making
life easier for a quicklook.

## CI/CD

This repository uses GitHub Actions to build, test and push the
resulting container image to an image registry.  If you fork this
repository and want to push the image, set the following **secrets**
in your repository settings on GitHub:

* `REGISTRY_SCOPE`: e.g. `quay.io/user-or-project-name`
* `REGISTRY_USERNAME`: registry account name (robot account recommended)
* `REGISTRY_PASSWORD`: registry password

You can extract both the account name and registry password by
base64-decoding an access token.  The account name and password are
separated by a colon character (`:`).
