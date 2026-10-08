# Research: Workshop VM Image

Findings marked **(measured)** were observed by booting the pinned base image on the maintainer's
Linux host on 2026-10-08, not taken from documentation.

## R1. Guest distribution and base image

- **Decision**: Debian 13 "trixie", official `generic` cloud image, pinned to build serial
  `20261001-2618`, for `amd64` and `arm64`.
- **Rationale**: **(measured)** kernel `6.12.111+deb13`, `CONFIG_BPF_LSM=y`,
  `CONFIG_DEBUG_INFO_BTF=y`, and `bpf` is already in the default `CONFIG_LSM` list, so
  `/sys/kernel/security/lsm` contains `bpf` on a stock boot with no kernel command-line change.
  The image is 415 MiB, boots under both BIOS and UEFI on amd64, and Debian publishes dated,
  immutable directories with `SHA512SUMS`.
- **Alternatives considered**:
  - Debian `genericcloud`: smaller, but its cloud kernel drops drivers for desktop hypervisors
    (VirtualBox/VMware emulated IDE/SATA/e1000). Rejected for cross-hypervisor reach.
  - Debian `nocloud`: no cloud-init, so there is nothing in the image to run provisioning without
    root-requiring offline tools.
  - Ubuntu 24.04 cloud image: workable (kernel 6.8), but older kernel, larger image, snapd, and
    BPF LSM needs an `lsm=` command-line edit. Kept as a possible later variant.
  - `debootstrap`/`mmdebstrap`/`mkosi` from scratch: needs root or user namespaces plus a
    bootloader install step; much more to maintain than customising a published image.

## R2. How to customise the image without root on the build host

- **Decision**: Boot the base image once in QEMU with a qcow2 overlay and let its built-in
  cloud-init run `scripts/provision.sh` as a user-data script. The seed is served over HTTP from
  the build host (`python3 -m http.server` on loopback) and discovered through the SMBIOS serial
  number: `-smbios 'type=1,serial=ds=nocloud;s=http://10.0.2.2:<port>/'`. The script powers the
  guest off when finished; the host then flattens and compresses the overlay.
- **Rationale**: **(measured)** works on the pinned image. It needs only QEMU and Python 3 on the
  host: no root, no loop devices, no libguestfs, and no ISO/FAT authoring tool. The same mechanism
  works for a cross-architecture (TCG-emulated) arm64 build.
- **Details learned (measured)**:
  - cloud-init retries a missing `network-config` and `vendor-data` for about 10 s each, so the
    seed serves both (empty `vendor-data`) to avoid 20 s of dead time.
  - Without a `network-config`, cloud-init writes `/etc/netplan/50-cloud-init.yaml` that matches
    the build VM's **MAC address**. Left in place, networking would break on every other
    hypervisor. Provisioning replaces it with a systemd-networkd rule matching by name (`e*`)
    and then removes cloud-init and netplan altogether.
  - The base image's root filesystem is 3 GiB; cloud-init grows it to the overlay size on first
    boot, before user scripts run.
- **Alternatives considered**:
  - NoCloud seed ISO (`cloud-localds`/`genisoimage`/`xorriso`): one more host package, none of
    which is installed by default on common distros or macOS.
  - `virt-customize`: convenient, but libguestfs is a heavy dependency, awkward on macOS, and
    cannot easily do cross-architecture package installs.
  - Packer: a second tool and a second configuration language for what is about 100 lines of shell.

## R3. Success/failure signalling from the guest

- **Decision**: The provisioning script logs to the serial console and prints a final marker line
  (`WORKSHOP-PROVISION-OK` or `WORKSHOP-PROVISION-FAILED`) before powering off. The host captures
  the serial port to a file, runs QEMU under `timeout`, and only produces the output image if the
  OK marker is present. The output is written to a temporary name and renamed at the end.
- **Rationale**: Satisfies FR-011 without needing SSH or a guest agent during the build.

## R4. Canonical image format and conversions

- **Decision**: Canonical artifact is a compressed **qcow2** (zlib, format v3) per architecture.
  Derived artifacts are produced with `qemu-img convert`:

  | Host tool | Format | How |
  |---|---|---|
  | QEMU/KVM, libvirt, GNOME Boxes, virt-manager (Linux) | qcow2 | native |
  | QEMU on macOS (HVF) and Windows (WHPX) | qcow2 | native |
  | UTM (macOS, incl. Apple silicon) | qcow2 | import as-is |
  | VirtualBox, VMware Workstation/Fusion (x86) | OVA (OVF 1.0 + stream-optimized VMDK) | `make ova` |
  | Hyper-V | VHDX | `make convert FORMAT=vhdx` |
  | anything else | VDI, VMDK, raw | `make convert FORMAT=…` |

- **Rationale**: No single disk format is opened natively by every desktop hypervisor, but qcow2
  is the one that (a) is compressed, keeping the download small, (b) is read directly by QEMU on
  all three operating systems, and (c) converts losslessly to every other format with the same
  tool that reads it. OVA is the de-facto import format shared by VirtualBox and VMware, and its
  stream-optimized VMDK is also compressed.
- **Alternatives considered**:
  - Raw: universal but 8 GiB uncompressed; over the 2 GiB release-asset limit even when sparse.
  - VHDX/VDI/monolithic VMDK as the release format: uncompressed, expected to exceed 2 GiB.
  - zstd-compressed qcow2: smaller, but some non-QEMU readers cannot open it. zlib is universal.
- **OVA hardware profile**: IDE disk controller, Intel E1000 NIC on NAT, 2 vCPU, 2 GiB RAM, BIOS
  firmware. IDE and E1000 are the lowest common denominator emulated by both VirtualBox and
  VMware and need no paravirtual drivers. OVA is produced for amd64 only; Apple silicon users are
  directed to UTM/QEMU with the arm64 qcow2.

## R5. Apple silicon

- **Decision**: Build a separate `arm64` image from Debian's arm64 cloud image. On an x86 build
  host this uses QEMU TCG emulation with UEFI firmware (AAVMF/edk2); it is slow but unattended.
- **Rationale**: x86 emulation on Apple silicon is too slow for an 80-minute hands-on session;
  an arm64 guest runs under Hypervisor.framework at native speed. BPF LSM is architecture
  independent on 6.12 (arm64 gained BPF trampoline/LSM support in 6.0+).
- **Alternatives considered**: ship amd64 only and ask Mac users to emulate — rejected.

## R6. Guest contents

- **Decision**: Install with `--no-install-recommends`: `clang llvm libbpf-dev bpftool libelf-dev
  zlib1g-dev pkgconf gcc libc6-dev make git vim nano less curl ca-certificates strace bpftrace
  tmux bash-completion man-db manpages-dev`. No kernel upgrade, no kernel header package, no
  C++ compiler (see R10 for what else is trimmed).
- **Rationale**: BPF LSM programs are built CO-RE style against `vmlinux.h` generated from
  `/sys/kernel/btf/vmlinux`, so kernel headers are unnecessary. Not upgrading the kernel keeps the
  running kernel identical to the pinned base image and avoids shipping two kernels.
- **Debian quirk handled**: on Debian the architecture-specific `asm/` headers live in
  `/usr/include/<triplet>/asm`, which `clang -target bpf` does not search, so any program that
  includes `<linux/…>` UAPI headers fails with `asm/types.h not found`. Provisioning adds the
  conventional `/usr/include/asm` symlink.

## R7. Portability of the finished image

- **Decision**: Before shutdown, provisioning (a) removes SSH host keys and installs a one-shot
  unit that runs `ssh-keygen -A` before `ssh.service`, (b) empties `/etc/machine-id`, (c) writes
  a name-based systemd-networkd rule with `RequiredForOnline=no` so boot never blocks on a
  missing NIC, (d) purges cloud-init, (e) removes the cloud image's default `debian` user, and
  (f) cleans apt caches and runs `fstrim` so the compressed image is small.
- **Rationale**: FR-009 and FR-010.

## R8. Automated verification

- **Decision**: `make test` boots the finished image with `-snapshot` (so the artifact is not
  modified) and a different MAC address from the build, logs in over SSH with the documented
  password (OpenSSH `SSH_ASKPASS_REQUIRE=force`, so no `sshpass` dependency), and runs
  `tests/guest/run.sh`. That runs `make` in `tests/guest/`, which generates `vmlinux.h`, compiles
  `deny_mkdir.bpf.c` with clang, generates a libbpf skeleton with bpftool, and builds the loader
  `deny_mkdir.c` with gcc. It starts the loader and asserts that creating a specifically named
  directory fails with "Operation not permitted" while another succeeds, then stops the loader
  and asserts the operation works again. Finally it runs a bpftrace program and a
  `gcc -flto -fsanitize` build.
- **Rationale**: Constitution principle IV. Logging in with the password over SSH also proves
  FR-008 and FR-010 (host keys were regenerated).

## R9. Package version pinning (accepted deviation)

- **Decision**: The base image is pinned and checksum-verified; Debian packages installed during
  provisioning come from the live `trixie` stable archive and are **not** pinned. Each build emits
  a package manifest (`*.packages.txt`) next to the image recording exact versions.
- **Rationale**: Pinning apt to `snapshot.debian.org` would make builds exactly repeatable but that
  service is slow and rate-limited, which makes builds unreliable. Debian stable only changes for
  security and point releases, and the kernel (the component the workshop depends on most) is
  fixed by the base image pin.
- **Alternatives considered**: snapshot.debian.org pin (can be added later as an opt-in variable).

## R10. Image size

- **Decision**: Trim the guest in provisioning rather than change the base image. **(measured,
  amd64)** disk usage went from 1465 MB to 986 MB and the compressed qcow2 from 633 MB to 403 MB.

  | Step | What it removes |
  |---|---|
  | dpkg `path-exclude` rules | translations, `/usr/share/doc` except copyright files, non-English man pages; `llvm-exegesis` (47 MB on its own) and six other LLVM developer tools; GCC's `lto-dump`; C++ standard library headers and static libraries; Vim translations, spell files and tutor |
  | Package choice | `gcc libc6-dev make` instead of `build-essential` (no g++) |
  | Purge after use | cloud-init, netplan, unattended-upgrades, the whole Python 3 stack, and `locales` (only C.UTF-8 was ever generated) |
  | Kernel module pruning | sound, wireless, Bluetooth, media, InfiniBand, IIO, staging, large GPU drivers, laptop platform and sensor drivers, Fibre Channel/SAS/RAID adapters, server-class Intel NICs and other physical NIC vendors, cluster and legacy filesystems, rarely used network protocols: 102 MB → 30 MB, which also shrinks the initramfs |
  | Journal | `/var/log/journal` is removed, so journald logs to memory and build-time logs are not shipped |

- **Rationale**: Kernel modules and the initramfs are already compressed, so they pass straight
  through into the image size; pruning them is worth more than their on-disk size suggests.
  Removing cloud-init needs a second provisioning stage in a transient systemd unit, because a
  process started by cloud-init is killed when the package is removed.
- **Kept on purpose**: IDE, AHCI, NVMe, virtio, VMware, Hyper-V, Xen, BusLogic and LSI storage
  drivers, USB and input, e1000/e1000e/pcnet32/rtl8139/vmxnet3; ext4, FAT, ISO, overlay, FUSE,
  9p and NFS client filesystems; netfilter; `git`, `vim` with syntax highlighting and help, man
  pages, `llvm-objdump`, `llvm-strip`, static libc.
- **Verified by booting (measured)**: besides the two smoke-test profiles, the pruned amd64
  image boots and gets network under QEMU with AHCI + e1000e, virtio-scsi + vmxnet3,
  NVMe + rtl8139, pvscsi + vmxnet3, LSI 53c895a + pcnet, USB storage, and UEFI firmware. QEMU's
  megasas and mptsas1068 controllers fail, but identically with the unpruned image (I/O errors
  from the emulation and a firmware read error respectively), so they are not regressions.
- **Alternatives considered**:
  - Debian's `genericcloud` kernel: smaller still, but drops the emulated hardware drivers that
    VirtualBox and VMware need (see R1).
  - Dropping `git` (about 50 MB installed with Perl) or swapping `vim` for `vim-tiny` (about
    40 MB): rejected as too costly for attendees for what they save.
- **Tried and reverted**: excluding GCC's `lto1`, the sanitizer runtimes, and the libclang C API
  library, and leaving out bpftrace, saved a further 33 MB, but GCC and bpftrace are required to
  work fully. The smoke test now checks `gcc -flto -fsanitize=address,undefined` and bpftrace.
- **Trade-offs to know about**: there is no C++ compiler (`sudo apt install g++` adds one), and
  deleting `/etc/dpkg/dpkg.cfg.d/workshop-slim` before installing stops the file exclusions.

## R11. Would another distribution be much smaller?

- **Decision**: Stay on Debian. No general-purpose distribution gets the download under 100 MB
  while the VM contains clang, GCC and bpftrace.
- **Evidence (measured)**: Alpine 3.24 with the equivalent package set, built in a container and
  archived, is 442 MB as tar.gz and 326 MB as tar.xz — no smaller than the Debian image (403 MB
  as compressed qcow2, 260 MB with xz). Step by step:

  | Alpine contents | tar.gz | tar.xz |
  |---|---|---|
  | base + `linux-virt` kernel + sshd | 64 MB | 60 MB |
  | + clang, gcc, libbpf, bpftool, make | 262 MB | 199 MB |
  | + git, vim, nano, strace, tmux | 277 MB | 210 MB |
  | + llvm tools | 321 MB | 241 MB |
  | + bpftrace | 442 MB | 326 MB |

  Alpine's LLVM is newer and larger (libLLVM 182 MB against Debian's 123 MB), and its bpftrace is
  built against a different LLVM major version from its clang, so a second complete LLVM is
  installed.
- **Alpine kernel caveats (measured from the shipped configs)**: `linux-virt` has
  `CONFIG_BPF_LSM=y` and BTF but `CONFIG_FUNCTION_TRACER` is not set, which the BPF trampoline
  that attaches LSM programs normally relies on; `linux-lts` has it, but its modules are 143 MB.
  Neither lists `bpf` in `CONFIG_LSM`, so an `lsm=` kernel argument would be needed. Whether LSM
  programs attach on `linux-virt` was not tested.
- **Other candidates (not measured; from their published images)**: Ubuntu, Fedora and Arch cloud
  images all start larger than Debian's before any toolchain is added, and use the same LLVM.
  Void and NixOS have no size advantage for this package set.
- **Where the floor is**: the LLVM libraries that clang needs (libLLVM, libclang-cpp, libz3) are
  about 215 MB on disk on Debian, GCC's compiler binaries about 65 MB, and a kernel with modules
  and initramfs about 65 MB that is already compressed. A sub-100 MB download would need a different
  workshop design, not a different distribution: for example compiling on the host, or shipping
  prebuilt BPF objects and only loading them in the VM.

## R12. Running on macOS

- **Decision**: Ship a prebuilt UTM virtual machine (`bpf-lsm-workshop-arm64.utm.zip`, built by
  `make utm ARCH=arm64`) as the primary path for Apple silicon Macs, with Homebrew QEMU as the
  fallback. Intel Macs use the amd64 qcow2 with QEMU or the OVA.
- **Rationale**: UTM is free, is the usual front end for QEMU on macOS, and stores a VM as a
  directory (`<name>.utm` containing `config.plist` and `Data/<disk>`), so the bundle can be
  generated on the Linux build host and opened with a double-click. Attendees configure nothing.
- **Bundle contents**: QEMU backend, configuration version 4; `aarch64` / `virt` / default CPU
  with the hypervisor enabled; UEFI boot (UTM creates the variable store on first start); the
  qcow2 as a VirtIO drive; no display, one built-in serial terminal (the guest runs a getty on
  `ttyAMA0`); "Emulated VLAN" networking with host `127.0.0.1:2222` forwarded to guest port 22.
  Keys and values were taken from the `Configuration/` sources of
  [utmapp/UTM](https://github.com/utmapp/UTM/tree/main/Configuration).
- **Not verified**: the bundle has not been opened in UTM; no Mac was available. Checked here:
  the plist parses and has every top-level key UTM's decoder requires, and the disk inside the
  zip passes `qemu-img check`. The same image boots under emulated `virt` + UEFI in `make test`.
- **Alternatives considered**:
  - UTM's Apple Virtualization backend: needs a raw disk, has no port forwarding, and UTM's own
    documentation warns of Linux guest kernel panics on some M1 configurations.
  - Lima: requires cloud-init in the guest, which the image removes.
  - VirtualBox 7.2 / VMware Fusion on Apple silicon: both run arm64 Linux guests, but would need
    a separate arm64 appliance (UEFI, no IDE) that cannot be tested here either.
  - OrbStack, Docker Desktop, Colima, Multipass: supply their own kernel or images, so the
    workshop kernel configuration is not guaranteed.

## R13. Building release files in CI

- **Decision**: A GitHub Actions workflow (`.github/workflows/images.yml`) runs `make check`,
  then builds and tests each architecture in a matrix on `ubuntu-24.04` runners. It uploads the
  images as artifacts. On a `v*` tag, a release job downloads the artifacts, runs `make dist`,
  and creates a **draft** release with `gh release create`.
- **Rationale**:
  - Hosted x86 runners have `/dev/kvm`. A udev rule lets the runner user open it
    ([actions/runner-images#7191](https://github.com/actions/runner-images/discussions/7191),
    [GitHub changelog](https://github.blog/changelog/2023-02-23-hardware-accelerated-android-virtualization-on-actions-windows-and-linux-larger-hosted-runners)).
  - The arm64 image is built with TCG emulation on the x86 runner. The hosted arm64 runners
    have no `/dev/kvm`, so they give no speed advantage
    ([Charmhub: ARM64 runners](https://charmhub.io/github-runner/docs/explanation-arm64)).
  - Every release file is below the 2 GiB limit for one release asset.
  - A draft release lets a person check the files before attendees see them.
  - The base image is cached with `actions/cache`, keyed on `versions.mk`.
  - Artifacts are uploaded with `compression-level: 0`, because the images are already compressed.
- **Alternatives considered**: self-hosted runners (more speed for arm64, but a machine to
  maintain); building in a container (QEMU in a container still needs `/dev/kvm`, so it adds
  nothing).
