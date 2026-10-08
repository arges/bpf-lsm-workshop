# Lab 02: Observe

**Goal:** find out which process calls, and with which arguments, before you decide anything.

> **Save point 02:** This directory is the completed state after adding caller and argument
> observation. Follow the slides in `labs/work`. Copy this directory there only to recover.

New in `hello_lsm.bpf.c`:

- `bpf_get_current_comm()` and `bpf_get_current_pid_tgid()`. The hook runs in the context of the
  process that made the system call. So "current" is the caller.
- `address->sa_family`. The program reads a field of a hook argument directly. The verifier
  knows the type of the argument from BTF.

## Run the save point

```sh
make load
make trace                              # second terminal
../tools/try-bind inet                  # family=2  (AF_INET)
../tools/try-bind alg hash sha256       # family=38 (AF_ALG)
nc -l 127.0.0.1 9999                    # Ctrl-C to stop
make unload
```

The output looks like this: `bind(): comm=try-bind pid=1234 family=2`.

## What to look at

- This is the first step of a real rollout: observe before you deny. Run a program like this on
  all your servers. Then you know which programs bind AF_ALG sockets for a good reason.
- `comm` has a maximum of 15 characters. The process sets its own `comm`, so `comm` can be
  false. Lab 05 shows why this is important.
