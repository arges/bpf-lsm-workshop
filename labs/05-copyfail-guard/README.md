# Lab 05: copyfail_guard

**Goal:** a Copy Fail mitigation that you can use on real systems.

> **Save point 05:** This directory is the completed mitigation and userspace loader.
> The slides build toward its components. Copy it to `labs/work` to run the integrated result.

The differences from lab 04:

| Lab 04 | Lab 05 |
|---|---|
| Denies every AF_ALG bind | Denies only the type `aead`, which has the bug. Hashes and plain ciphers still work. |
| Allow list of process names. An attacker can fake a name. | Allow list of executable files (device and inode). A process cannot change these. |
| The allow list is in the program code. | The allow list is in a BPF map. The loader fills it from `--allow PATH`. |
| `bpf_printk()` | Structured denial events to user space through a ring buffer |
| `bpftool` loads it. | It has its own loader, which uses a libbpf skeleton. |

Files:

- `copyfail_guard.bpf.c`: the kernel side.
- `copyfail_guard.c`: the loader. It reads the options, fills the allow list and prints events.
- `copyfail_guard.h`: the structures that the two files share.

## Run the save point

```sh
make
cp ../tools/try-bind ../tools/trusted-app
sudo ./copyfail_guard --allow ../tools/trusted-app
```

In a second terminal:

```sh
../tools/try-bind alg hash sha256                                   # OK: not AEAD
../tools/try-bind alg aead 'authencesn(hmac(sha256),cbc(aes))'      # Operation not permitted
../tools/trusted-app alg aead 'authencesn(hmac(sha256),cbc(aes))'   # OK: allowed executable

mkdir -p /tmp/fake && cp ../tools/try-bind /tmp/fake/trusted-app
/tmp/fake/trusted-app alg aead 'gcm(aes)'                           # Operation not permitted
```

The loader prints a line for each denied bind:

```text
DENIED: pid=1432 uid=1000 comm=try-bind algorithm=authencesn(hmac(sha256),cbc(aes))
DENIED: pid=1436 uid=1000 comm=trusted-app algorithm=gcm(aes)
```

Push Ctrl-C to stop the loader. The mitigation stops when the loader stops.

## What to look at

- The last denial above has the right name but the wrong file. A name can be false. An inode
  cannot.
- A real rollout observes first (as in lab 02) to find the programs that need AF_ALG AEAD,
  then puts them on the allow list before it enforces.
- The hook gives the address only as a general `struct sockaddr`. So the program uses
  `bpf_probe_read_kernel()` to read the `struct sockaddr_alg` from the `address` argument.

## Limits

- The mitigation stops when the loader stops. A production version pins the program and its maps
  in `/sys/fs/bpf`. The init system starts it before any untrusted program runs.
- The allow list identifies a file, not the contents of the file. If someone replaces an allowed
  file in place, the new file is also allowed. So the users that you defend against must not be
  able to write to the files on the list.
- On some filesystems, such as overlayfs and btrfs subvolumes, the device number from `stat()` is
  not the same as the kernel value. On these filesystems, the loader needs a different way to
  identify files.
- This program mitigates the bug. It does not fix it. To fix the bug, install a kernel that has
  the fix.
