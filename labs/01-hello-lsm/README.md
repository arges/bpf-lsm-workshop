# Lab 01: Hello, LSM

**Goal:** attach a BPF program to an LSM hook, and see it run.

> **Save point 01:** This directory is the completed state after the first hands-on section.
> Follow the slides in `labs/work`. Copy this directory to `labs/work` only to recover.

All later labs use the structure in `hello_lsm.bpf.c`:

- `#include "vmlinux.h"`: all the kernel types. The build makes this file from the running kernel.
- `LICENSE`: the kernel does not let a program use GPL-only helpers if the program is not GPL
  compatible.
- `SEC("lsm/socket_bind")`: the hook that the program attaches to.
- `BPF_PROG(name, <hook arguments>, int ret)`: the arguments of the hook, and the decision of the
  LSM before this one.
- The return value: `0` allows the operation. A negative error number denies it.

## Run the save point

```sh
make load
make trace                      # second terminal
../tools/try-bind inet          # third terminal, or the first one
```

Each `bind()` on the system prints `hello from the socket_bind LSM hook`.

```sh
sudo bpftool prog show name hello_lsm
make unload
```

## What to look at

- You did not reboot, and you did not build a kernel module.
- Run `cat /sys/kernel/security/lsm`. The list must contain `bpf`, or BPF LSM programs do not work.
- Change `return ret;` to `return -1;`, then load the program again. What stops working? Unload
  the program quickly.
