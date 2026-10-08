# Lab 03: The first denial

**Goal:** make the kernel deny an operation.

> **Save point 03:** This directory is the completed state after the first denial.
> Follow the slides in `labs/work`. Copy this directory there only to recover.

New in `hello_lsm.bpf.c`:

- `return -EPERM;`. The `bind()` of the caller fails with "Operation not permitted".
- `if (ret) return ret;`. If an LSM before this one denied the operation, keep that decision.
- `bpf_strncmp()`. The program compares the process name with a fixed string.

## Run the save point

```sh
make load
nc -l 127.0.0.1 9999            # nc: Operation not permitted
../tools/try-bind inet          # bind(AF_INET): OK
make unload
nc -l 127.0.0.1 9999            # listens again; Ctrl-C to stop
```

## What to look at

- The denial starts immediately, for all users. It also denies root:
  `sudo nc -l 127.0.0.1 9999`.
- It is also easy to go around: `cp /usr/bin/nc ./notnc && ./notnc -l 127.0.0.1 9999`. The
  attacker controls the name. A deny list of names is not a mitigation.
- The verifier checks the return value. An LSM program can return only `0` or a negative error
  number.
