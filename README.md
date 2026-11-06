# bpf-lsm-workshop

This repository builds the virtual machine (VM) for the hands-on workshop
[Mitigating All The Vulns with BPF-LSM: A Tutorial](https://pretalx.com/txlf2026/speaker/QDSWNE/)
at Texas Linux Fest 2026. It also holds the workshop labs.

**[View the slides in your browser](https://arges.github.io/bpf-lsm-workshop/)**
(Use the arrow keys to move between slides.)

The repository contains no disk images. `make image` does these steps:

1. Download a Debian 13 cloud image and check its checksum.
2. Boot the image one time in QEMU and install the BPF tools.
3. Write a compressed qcow2 file of about 400 MB.

We publish the finished images as GitHub release files.

**Are you an attendee?** You only need a released image. It already contains the labs. Read
[docs/running.md](docs/running.md) to start it.

The [slides](slides/slides.md) guide attendees through typing each command and code change. The
numbered directories in [labs/](labs/) provide save points for recovery and review.

## Slides

- [View the slides in your browser](https://arges.github.io/bpf-lsm-workshop/).
- The source is [slides/slides.md](slides/slides.md). It uses [Marp](https://marp.app/).
- A GitHub workflow (`.github/workflows/slides.yml`) publishes the slides. It runs after each
  push to `main` that changes `slides/`.
- To view them offline, run `make slides` and open `slides/slides.html` in a browser. This needs
  Node.js.

## Download the image

These links always get the files from the newest release:

| Your computer | File |
|---|---|
| Linux, Intel/AMD | [bpf-lsm-workshop-amd64.qcow2](https://github.com/arges/bpf-lsm-workshop/releases/latest/download/bpf-lsm-workshop-amd64.qcow2) |
| Mac, Apple silicon | [bpf-lsm-workshop-arm64.utm.zip](https://github.com/arges/bpf-lsm-workshop/releases/latest/download/bpf-lsm-workshop-arm64.utm.zip) (UTM) or [bpf-lsm-workshop-arm64.qcow2](https://github.com/arges/bpf-lsm-workshop/releases/latest/download/bpf-lsm-workshop-arm64.qcow2) (QEMU) |
| Mac, Intel | [bpf-lsm-workshop-amd64.qcow2](https://github.com/arges/bpf-lsm-workshop/releases/latest/download/bpf-lsm-workshop-amd64.qcow2) (QEMU) or [bpf-lsm-workshop-amd64.ova](https://github.com/arges/bpf-lsm-workshop/releases/latest/download/bpf-lsm-workshop-amd64.ova) (VirtualBox/VMware) |
| Windows, Intel/AMD | [bpf-lsm-workshop-amd64.ova](https://github.com/arges/bpf-lsm-workshop/releases/latest/download/bpf-lsm-workshop-amd64.ova) (VirtualBox/VMware), [bpf-lsm-workshop-amd64.vhdx.zip](https://github.com/arges/bpf-lsm-workshop/releases/latest/download/bpf-lsm-workshop-amd64.vhdx.zip) (Hyper-V) or [bpf-lsm-workshop-amd64.qcow2](https://github.com/arges/bpf-lsm-workshop/releases/latest/download/bpf-lsm-workshop-amd64.qcow2) (QEMU) |
| All | [SHA256SUMS](https://github.com/arges/bpf-lsm-workshop/releases/latest/download/SHA256SUMS), to check the download |

All releases are on the [Releases page](https://github.com/arges/bpf-lsm-workshop/releases).

## What is in the VM

- Debian 13 "trixie" with kernel 7.2 from trixie-backports. The `bpf` LSM is active, and the kernel has BTF type data.
- `clang`, `llvm`, `libbpf-dev`, `bpftool` with native JIT disassembly, `bpftrace`, `gcc`,
  `make`, `git`, `vim`, `nano`, `strace` and `tmux`.
- The user `workshop` with the password `workshop`. `sudo` needs no password. SSH is on.
- The workshop snapshots and tools in `~/bpf-lsm-workshop/labs`.

The image is small on purpose. It has no C++ compiler, no translations, and no kernel modules
for hardware that a VM does not have. To add a package, run `sudo apt update` and then
`sudo apt install <package>`.

The password is public on purpose. Use the VM only for teaching. Keep it on NAT networking.
Do not connect it to a network that you do not trust.

## Build the image

You need a Linux host with these tools: `make`, QEMU (`qemu-system-x86_64` and `qemu-img`),
`curl`, `python3`, `tar`, `sha256sum` and an OpenSSH client. You do not need root. With KVM, the
build takes about one minute plus the download time.

```sh
make image      # build/bpf-lsm-workshop-amd64.qcow2
make test       # boot the image, then build and test the BPF programs inside it
```

### Work in the VM over SSH

The recommended workflow runs QEMU in the background and uses the host terminal for SSH:

```sh
make start      # start the VM and wait until SSH is ready
make ssh        # open an SSH session
make stop       # shut down the VM
```

The `workshop` account has the password `workshop` and password-less `sudo`. `make start` uses a
copy-on-write disk at `build/run-amd64.qcow2`, so it does not change the release image. To use a
different host port, pass the same value to each command, for example `SSH_PORT=2223`.

Use `make run` instead when you need the serial console. Leave it open in one terminal and run
`make ssh` in another. Push `Ctrl-a`, then `x`, to stop the serial-console VM.

### Use Visual Studio Code

Install the **Remote - SSH** extension. Add this host to `~/.ssh/config`:

```sshconfig
Host bpf-lsm-workshop
    HostName 127.0.0.1
    Port 2222
    User workshop
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

Run `make start`, select **Remote-SSH: Connect to Host** in Visual Studio Code, and select
`bpf-lsm-workshop`. Enter `workshop` when Visual Studio Code asks for the password. You can then
open a lab directory in the VM and use its terminal, compiler, and BPF tools directly.

Other architectures and formats:

```sh
make image test ARCH=arm64    # for Apple silicon; emulated on an x86 host, needs
                              # qemu-system-aarch64 and AArch64 UEFI firmware (AAVMF/edk2)
make ova                      # OVA for VirtualBox / VMware (amd64)
make vhdx                     # zipped VHDX for Hyper-V (amd64)
make utm ARCH=arm64           # UTM virtual machine for Apple silicon Macs
make convert FORMAT=vhdx      # or vdi, vmdk, raw
```

Run `make` with no target to see all targets. The full interface is in
[specs/001-workshop-vm-image/contracts/make-targets.md](specs/001-workshop-vm-image/contracts/make-targets.md).

## Make a release

GitHub Actions builds the images. The workflow is in
[.github/workflows/images.yml](.github/workflows/images.yml).

- On each push to `main` and on each pull request, the workflow builds and tests the amd64 and
  arm64 images. It also runs `make check`. The images are workflow artifacts for 14 days.
- When you push a tag that starts with `v`, the workflow also makes a **draft** release with the
  images and `SHA256SUMS`. Read the draft, then publish it on GitHub.

```sh
git tag v2026.11
git push origin v2026.11
```

To make the release files on your own computer, run these commands:

```sh
make image test
make image test ARCH=arm64
make ova
make vhdx
make utm ARCH=arm64
make dist                     # dist/ with images, package manifests and SHA256SUMS
gh release create v2026.11 dist/* --title "Workshop VM" --notes "See docs/running.md"
```

## Change the base image

[versions.mk](versions.mk) sets the base image by its build serial and its SHA-512 checksum. To use
a newer base image, follow these steps:

1. Change `BASE_SERIAL` and both checksums.
2. Build the image again.
3. Run the tests again.

The build does not fix the versions of the Debian packages that it installs. Each build records the
installed versions in `build/bpf-lsm-workshop-<arch>.packages.txt`.

## Project organization

The project uses [Spec Kit](https://github.com/github/spec-kit). The project principles are in
[.specify/memory/constitution.md](.specify/memory/constitution.md). Each feature has a
specification, a plan and a task list in [specs/](specs/).

## License

[MIT](LICENSE). The BPF programs have a dual MIT/GPL-2.0 license.
