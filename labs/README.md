# Labs

The slides are the workshop's primary path: participants type each command and code change in
`labs/work`. The five numbered directories are complete, known-good snapshots of that progression.
They are save points for recovery, comparison and self-paced review—not five separate exercises.

| Save point | State captured | Program |
|---|---|---|
| [01-hello-lsm](01-hello-lsm/) | A minimal program attaches to `socket_bind`, logs and preserves the prior verdict. | `hello_lsm` |
| [02-observe](02-observe/) | The program adds caller identity and the socket-family argument. | `hello_lsm` |
| [03-deny-comm](03-deny-comm/) | The first policy decision denies one process name. | `hello_lsm` |
| [04-deny-af-alg](04-deny-af-alg/) | The decision narrows to AF_ALG and allows selected process names. | `hello_lsm` |
| [05-copyfail-guard](05-copyfail-guard/) | The full mitigation adds an exact match, executable allow list and event stream. | `copyfail_guard` |

Every snapshot attaches to `socket_bind`. Each one preserves the previous ideas and adds one new
decision or data path.

## The target: Copy Fail

[Copy Fail (CVE-2026-31431)](https://www.helpnetsecurity.com/2026/04/30/copyfail-linux-lpe-vulnerability-cve-2026-31431/)
is a logic bug in `algif_aead`, the kernel interface for AEAD sockets. The bug is in kernels
from 2017 and later. Any local user can write four bytes into the page cache of any file that the
user can read. That is enough to get root: the attacker changes a setuid program in the page cache.
The exploit does not need a race. The same exploit works on many distributions without changes.

An exploit must do these steps in this order:

1. Call `socket(AF_ALG, SOCK_SEQPACKET, 0)`.
2. Call `bind()` on that socket with an AEAD algorithm, `authencesn(...)`.
3. Set a key, and call `accept()` to get a request socket.
4. Call `splice()` to bring in pages of the target file. Then call `sendmsg()` and `recvmsg()`.

Step 2 is the choke point:

- Almost no program on a normal system binds an AF_ALG AEAD socket.
- The `socket_bind` LSM hook sees every bind.
- A BPF LSM program can deny the bind on a running kernel. You do not need to reboot.

[Cloudflare described](https://blog.cloudflare.com/copy-fail-linux-vulnerability-mitigation/)
this method for its own servers. First, find the programs that use AF_ALG for a good reason. Then
deny `socket_bind` for all other programs.

The kernel in the workshop VM already has the fix. The labs contain no exploit code.
`tools/try-bind` does only steps 1 and 2. That is enough to see if a program stops the attack.

## How to use the save points

Follow `slides/slides.md` and do the work in `labs/work`. To start with an empty workspace:

```sh
cd ~/bpf-lsm-workshop/labs
rm -rf work
mkdir work
cd work
```

If you fall behind or an experiment breaks, replace `work` with the latest completed snapshot:

```sh
cd ~/bpf-lsm-workshop/labs
rm -rf work
cp -a 02-observe work             # choose the checkpoint you just completed
cd work
```

The copied Makefile still works because `work` remains under `labs/`, next to `common.mk`,
`vmlinux.h` and `tools/`. Build and inspect a checkpoint with:

```sh
make                              # build
make load                         # load and attach (uses sudo)
make trace                        # second terminal. Ctrl-C to stop
make unload                       # detach and remove
```

Checkpoint 05 has its own loader and does not use `make load`. Its README gives the commands.
Build `tools/try-bind` one time with `make -C ../tools` from `labs/work`.

`sudo bpftool prog show` lists loaded programs. A reboot removes every lab program and returns the
VM to a known state. `./test.sh` from `labs/` verifies all five snapshots.

## Hooks are not system calls

A BPF LSM program does not attach to `bind(2)`. It attaches to a security hook. The kernel calls
this hook during `bind(2)`, after it copies the arguments into the kernel and checks them. This
is important:

- The program sees kernel objects, such as `struct socket` and the kernel copy of the address.
  It does not see user pointers. User pointers can change after the check.
- One hook covers every path to the operation. This includes paths that do not use the usual
  system call, such as `io_uring` and compat system calls.
- The kernel source lists the hooks and their arguments in `include/linux/lsm_hook_defs.h`. In
  the VM, `sudo bpftool btf dump file /sys/kernel/btf/vmlinux | grep bpf_lsm_` lists them.
