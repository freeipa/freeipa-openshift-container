# DevOps Documentation

## Setting up the pipeline

This repo include [travis-ci](https://www.travis-ci.org) integration, which
need some variables to be set up so it can works properly. Below can be seen
the needed variables:

- Secrets:
  - **DOCKER_USERNAME**: The username to access the container image registry.
  - **DOCKER_PASSWORD**: The password to access the container image registry.

- Variables:
  - **IMAGE_TAG_BASE**: This variable store the base tag that is used to
    derivate the name of all the images pushed to the registry. The first
    component is used to know which is the registry where to be logged in.

The images delivered can be found at: [quay.io](https://quay.io/freeipa/freeipa-openshift-container).

> Pull Requests does not generate any delivery for security reasons.

## About `dive` tool

The [dive](https://github.com/wagoodman/dive) tool is used to analyze the
image layer size. It can works standalone, or in a pipeline. Actually it
generates a report but does not break the pipeline. The report is just
informative so far.

This tool use the `.dive-ci.yml` file to set up the behavior. For more
information about the parameters inside, see the official documentation
[here](https://github.com/wagoodman/dive#ci-integration).

## About hadolint

This is the lint tool for Dokerfiles. The rules can be disbled for the current
line as described below:

```dockerfile
# hadolint disable=sc2043
```

The current set of rules can be seen [here](https://github.com/hadolint/hadolint#rules).
