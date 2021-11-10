# Entrypoint

Synced to init-data at 73940d4 git state.

This directory contain a set of shell scripts that are proposed as a change to
improve modularity and flexibility for the init-data. This is used actually
to override the entrypoint in freeipa-openshift-container; the current change
allow to implement unit tests by using BATS framework; we can find the the
unit tests at `tests/unit` directory. Below are the files provided at `init`
directory:

```raw
.
├── README.md
├── init.sh
├── includes.inc.sh
├── tasks.inc.sh
├── utils.inc.sh
├── container.inc.sh
└── ocp4.inc.sh
```

This directory content is copied to `/usr/local/share/ipa-container` into
the container.

- `README.md`: This file which provide documentation and file descriptions.

- `init.sh`: This is the entrypoint used for the container. It just include
  the list of includes (where more modules can be added/injected). It just
  define the directory where the files are stored, load the list of includes
  and launch the execution for the list of steps.

- `includes.inc.sh`: The only responsability of this file is to define the
  list of includes. It contain to placeholder to make easy to insert at
  the beginning or at the end more includes into th list for other
  Dockerfile that could extend from this. Such as:

  ```shell
  sed -i 's/^#.\+includes:end/source \"\$\{INIT_DIR\}\/ocp4\.inc\.sh\"\n&./g' /usr/local/share/ipa-container/includes.inc.sh
  ```

- `utils.sh`: This define some simple and stupid functions that sometimes
  only contains an expression. The reason of making that is that the unit
  tests can mock functions but not expressions. Another reason is that
  some commands can not be mocked because interfire into the well
  behaviour of BATS framework and modules.

- `tasks.inc.sh`: Implement the basic infrastructure to manage the list
  of steps, so it allows other modules to modify the list dynamically
  before the steps are executed.

- `container.inc.sh`: This file implement the current `init-data`
  behaviour. It does not add new behaviours, only express the current ones
  in decoupled functions (steps). The name for the functions here is
  important because it is checked by the `tasks.inc.sh` module when they
  are added, updated, or deleted. The syntax for the steps functions is:

  ```raw
  function module_step_myfunction { : ; }
  ```

  In `container.inc.sh` all the steps functions start by `container_step_*`.
  tasks check the string passed match with a function and the name match
  the above pattern for early error detection.

  We will see that some `helper` functions are defined. It has been
  followed the following criteria to name this kind of functions:

  ```raw
  function module_helper_myfunction { : ; }
  ```

- `ocp4.inc.sh': It includes the changes for hacking the container
  and allow it work as needed in OpenShift.

