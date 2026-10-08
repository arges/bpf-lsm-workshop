# Implementation Plan: Workshop VM Image

**Branch**: `001-workshop-vm-image` | **Date**: 2026-10-08 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-workshop-vm-image/spec.md`

## Summary

`make image` downloads a pinned, checksum-verified Debian 13 cloud image, boots it once in QEMU
with a throwaway overlay, lets cloud-init run a provisioning script served from the build host,
and writes a compressed qcow2 with the BPF toolchain installed. `make test` boots that artifact
and proves a BPF LSM program compiles, loads, and denies an operation. `make ova` / `make convert`
derive other hypervisor formats with `qemu-img`, and `make dist` assembles release files with
checksums. See [research.md](research.md) for the decisions behind each step.

## Technical Context

**Language/Version**: GNU Make ≥ 3.81, POSIX `sh` scripts; one C file (BPF, compiled in the guest)

**Primary Dependencies**: QEMU (`qemu-system-x86_64` and/or `qemu-system-aarch64`, `qemu-img`),
`curl`, `sha512sum`/`sha256sum`, `python3` (stdlib HTTP server only), OpenSSH client ≥ 8.4 (tests),
`tar`. For arm64: an AArch64 UEFI firmware file (AAVMF/edk2).

**Storage**: Files only — `cache/` (downloads), `build/` (work + images), `dist/` (release files);
all git-ignored

**Testing**: `make test` (boot + in-guest BPF LSM smoke test); `make check` (shellcheck, if present)

**Target Platform**: Build host: Linux x86_64 (arm64 Linux expected to work). Guest: Debian 13,
amd64 and arm64. Run hosts: Linux, macOS (Intel/Apple silicon), Windows

**Project Type**: Build tooling (Makefile + scripts)

**Performance Goals**: Native-arch build under 15 minutes with KVM (SC-001); cross-arch build under
emulation is allowed to take hours

**Constraints**: No root on build host; each release file < 2 GiB; repository < 1 MB; no
interactive prompts

**Scale/Scope**: 2 architectures, 1 canonical format, 4 derived formats, about 40 attendees

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. Recipes, Not Artifacts | PASS | Only text files in the repo; `cache/ build/ dist/` ignored |
| II. Pinned, Verified Inputs | PASS with deviation | Base image pinned by serial + SHA-512. Debian packages are not version-pinned (see Complexity Tracking) |
| III. Runs Where Attendees Are | PASS | qcow2 canonical; OVA/VHDX/VDI/VMDK derived by `qemu-img`; arm64 image for Apple silicon; untested paths labelled in `docs/running.md` |
| IV. Proven by Booting | PASS | `make test` boots the artifact and exercises a real BPF LSM denial; build fails without the provisioning OK marker |
| V. Small Surface, Few Dependencies | PASS with deviation | Make + sh + QEMU, no root. Adds `python3` on the build host (see Complexity Tracking) |
| Workshop Safety Constraints | PASS | NAT only, SSH forward bound to 127.0.0.1, host keys and machine-id regenerated on first boot, credentials documented as public |

Post-design re-check: unchanged; no new violations introduced by the Phase 1 design.

## Project Structure

### Documentation (this feature)

```text
specs/001-workshop-vm-image/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── make-targets.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Makefile                 # user-facing targets (see contracts/make-targets.md)
versions.mk              # pinned base image serial and SHA-512 per architecture
scripts/
├── lib.sh               # shared: arch mapping, accelerator and firmware detection, QEMU base args
├── fetch.sh             # download to .part, verify SHA-512, rename
├── build-image.sh       # host side: overlay, HTTP seed, boot, marker check, compress
├── provision.sh         # guest side: runs as cloud-init user-data
├── run-vm.sh            # boot an image interactively (Linux/macOS)
├── ssh-vm.sh            # password SSH into a running VM without sshpass
└── make-ova.sh          # stream-optimized VMDK + OVF + manifest → .ova
tests/
├── smoke-test.sh        # host side: boot with -snapshot, SSH in, run guest test
└── guest/
    ├── run.sh           # guest side: build, load, assert denial, unload, check tools
    ├── Makefile         # vmlinux.h → BPF object (clang) → skeleton (bpftool) → loader (gcc)
    ├── deny_mkdir.bpf.c # minimal BPF LSM program
    └── deny_mkdir.c     # libbpf skeleton loader
docs/
└── running.md           # per-platform run instructions for attendees
README.md
.gitignore
```

**Structure Decision**: Flat build-tooling layout. The Makefile is a thin dispatcher that owns
dependency tracking (what needs rebuilding); each script does one job and can be run by hand. The
guest-side provisioning script is a single self-contained file because it is served verbatim as
cloud-init user-data.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Principle II: Debian packages are not version-pinned | Reliable builds from the regular Debian mirror network | Pinning to snapshot.debian.org is slow and rate-limited; kernel is already fixed by the base image pin, and each build records a package manifest for traceability |
| Principle V: `python3` is an extra build-host dependency | Serves the cloud-init seed over HTTP so no ISO/FAT authoring tool, loop device, or root is needed | A seed ISO needs `genisoimage`/`xorriso`/`cloud-localds`, none of which is installed by default; Python 3 is present on effectively every Linux build host |
