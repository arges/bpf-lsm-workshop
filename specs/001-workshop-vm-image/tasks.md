---

description: "Task list for the Workshop VM Image feature"
---

# Tasks: Workshop VM Image

**Input**: Design documents from `/specs/001-workshop-vm-image/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/make-targets.md, quickstart.md

**Tests**: Included. The spec (FR-013) and constitution principle IV require an automated
boot-and-load test; it is the deliverable of User Story 2.

**Organization**: Tasks are grouped by user story so each story can be implemented and verified
on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story the task belongs to (US1–US4)

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Repository skeleton and pins

- [X] T001 Create `.gitignore` ignoring `cache/`, `build/`, `dist/`, `*.part`, `*.tmp`, editor/OS files
- [X] T002 [P] Create `versions.mk` with `DEBIAN_VERSION`, `DEBIAN_RELEASE`, `BASE_SERIAL`, and `BASE_SHA512_amd64` / `BASE_SHA512_arm64` taken from the dated `SHA512SUMS` on cloud.debian.org
- [X] T003 [P] Create `Makefile` skeleton: include `versions.mk`, `ARCH` auto-detection, variable defaults from contracts/make-targets.md, `help` as default target, `clean`, `distclean`, `check`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared host-side helpers every later script uses

- [X] T004 Create `scripts/lib.sh`: `die`/`need` helpers, host→Debian arch mapping, accelerator detection (kvm / hvf / tcg), AArch64 firmware lookup with `AAVMF_CODE` override, and a function emitting the per-arch base QEMU arguments (machine, cpu, accel, memory, cpus, firmware)
- [X] T005 [P] Create `scripts/fetch.sh <url> <sha512> <out>`: download to `<out>.part`, verify SHA-512, rename; delete the partial file and exit non-zero on mismatch
- [X] T006 Add the `fetch` target and the `cache/…qcow2` file rule to `Makefile`

**Checkpoint**: `make fetch` downloads and verifies the base image

---

## Phase 3: User Story 1 - Maintainer builds the image with one command (Priority: P1) 🎯 MVP

**Goal**: `make image` produces `build/bpf-lsm-workshop-<arch>.qcow2` unattended and without root

**Independent Test**: quickstart.md §1

- [X] T007 [US1] Create `scripts/provision.sh` (guest side, per research R6/R7): log to console, failure trap printing `WORKSHOP-PROVISION-FAILED`, install packages with `--no-install-recommends`, `/usr/include/asm` symlink, `workshop` user with password and NOPASSWD sudo, sshd password auth drop-in, first-boot host key unit, name-based netplan file, `/etc/issue` and `/etc/motd`, assert `bpf` in `/sys/kernel/security/lsm`, remove `debian` user, disable cloud-init, empty machine-id, clean apt and logs, `fstrim`, print package manifest between markers, print `WORKSHOP-PROVISION-OK`, power off
- [X] T008 [US1] Create `scripts/build-image.sh <arch> <base> <out>` (host side, per research R2/R3): temp work dir under `build/`, qcow2 overlay sized `DISK_SIZE`, seed dir (`meta-data`, `user-data`, empty `vendor-data`, `network-config`), HTTP server on a free loopback port, QEMU under `timeout` with serial log, cleanup trap, require OK marker, extract package manifest, `qemu-img convert -c` to `<out>.tmp` then rename
- [X] T009 [US1] Add the `image` target and `build/bpf-lsm-workshop-$(ARCH).qcow2` rule to `Makefile`, depending on the base image, `versions.mk`, and both scripts
- [X] T010 [US1] Run `make image` for amd64 and fix defects until it produces the image; record the size and build time

**Checkpoint**: A bootable workshop image exists for amd64

---

## Phase 4: User Story 2 - The image is proven fit for the workshop (Priority: P2)

**Goal**: `make test` proves BPF LSM works in the artifact; `make run` / `make ssh` give a shell

**Independent Test**: quickstart.md §2

- [X] T011 [P] [US2] Create `tests/guest/deny_mkdir.bpf.c`: `lsm/inode_mkdir` program returning `-EPERM` when the new directory is named `bpf-lsm-denied`
- [X] T012 [P] [US2] Create `tests/guest/run.sh`: check `bpf` is an active LSM, generate `vmlinux.h`, compile with clang, load with `bpftool prog load … autoattach`, assert denied/allowed mkdir, unload, assert allowed again, print `SMOKE-TEST-PASS`
- [X] T013 [P] [US2] Create `scripts/ssh-vm.sh`: password SSH to `workshop@127.0.0.1:$SSH_PORT` using `SSH_ASKPASS_REQUIRE=force`, without touching the user's `known_hosts`
- [X] T014 [US2] Create `tests/smoke-test.sh <arch> <image>`: boot with `-snapshot`, a MAC different from the build's, and a free forwarded port; wait for SSH; copy `tests/guest/` in and run it; always kill QEMU on exit; optional `HW=legacy` to boot with IDE + e1000 like the OVA profile
- [X] T015 [P] [US2] Create `scripts/run-vm.sh <arch> <image>`: create `build/run-<arch>.qcow2` overlay on first use, boot with serial console on stdio and SSH forwarded on loopback
- [X] T016 [US2] Add `test`, `run`, `ssh` targets to `Makefile`
- [X] T017 [US2] Run `make test` on the amd64 image and fix defects until it prints `SMOKE-TEST-PASS`

**Checkpoint**: The amd64 image is verified end to end

---

## Phase 5: User Story 3 - Attendees on macOS and Windows can run the image (Priority: P3)

**Goal**: Derived formats, an arm64 image, and per-platform instructions

**Independent Test**: quickstart.md §3

- [X] T018 [P] [US3] Create `scripts/make-ova.sh <qcow2> <ova>`: stream-optimized VMDK, OVF 1.0 descriptor (IDE disk, E1000 NAT NIC, 2 vCPU, 2 GiB), SHA-256 manifest, ustar archive in the order ovf, mf, vmdk
- [X] T019 [US3] Add `ova` and `convert FORMAT=…` targets to `Makefile`
- [X] T020 [US3] Run `make ova` and `make convert FORMAT=vhdx`; check the OVF is well-formed XML and run `tests/smoke-test.sh` with `HW=legacy` against the OVA's VMDK
- [X] T021 [US3] Run `make image ARCH=arm64` and `make test ARCH=arm64` (TCG on an x86 host) and fix arch-specific defects
- [X] T022 [P] [US3] Write `docs/running.md`: download + checksum verification, then per-platform steps (Linux QEMU/KVM, macOS QEMU/UTM, Windows VirtualBox/VMware/QEMU/Hyper-V), with every unexercised path marked untested

**Checkpoint**: Every in-scope host platform has a documented path

---

## Phase 6: User Story 4 - Maintainer publishes release files (Priority: P4)

**Goal**: `make dist` produces release-ready files with checksums

**Independent Test**: quickstart.md §4

- [X] T023 [US4] Add the `dist` target to `Makefile`: copy existing images, OVA, and package manifests into `dist/`, fail if any file is ≥ 2 GiB, write `SHA256SUMS`
- [X] T024 [US4] Run `make dist` and verify with `sha256sum -c`

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T025 [P] Write `README.md`: what this is, prerequisites, build/test/run/release commands, credentials and safety note, link to `docs/running.md`
- [X] T026 Run `make check` (shellcheck) if available and fix findings; otherwise run `sh -n` on every script — shellcheck was not installed on the build host, so only the `sh -n` syntax check has been run
- [X] T027 Walk through quickstart.md including the checksum-mismatch failure check and the "second `make image` does nothing" check; confirm the repository is under 1 MB excluding ignored directories

---

## Phase 8: Follow-up — Image Size

- [X] T028 Trim the guest in `scripts/provision.sh` per research R10 (dpkg path excludes, leaner package list, purge cloud-init/netplan/Python in a second stage, prune kernel modules) and re-run `make test` for both architectures and with `HW=legacy`
- [X] T029 Keep GCC complete and install bpftrace in `scripts/provision.sh`; turn the smoke test into a small buildable BPF LSM project (`tests/guest/Makefile`, `deny_mkdir.bpf.c`, gcc-built loader `deny_mkdir.c`) and check bpftrace and `gcc -flto -fsanitize` in `tests/guest/run.sh`
- [X] T030 Second trimming pass in `scripts/provision.sh` (deeper module pruning, more path excludes, purge `locales`, volatile journal), boot-tested on additional emulated controllers; compare against Alpine (research R11)
- [X] T031 Add `scripts/make-utm.sh` and the `utm` target: package the arm64 image as a UTM bundle (research R12); include it in `make dist`; document it in `docs/running.md` as untested
- [X] T032 Add `.github/workflows/images.yml`: lint, build and test both architectures on GitHub-hosted runners, upload the images as artifacts, and make a draft release on `v*` tags (research R13). Fix the shellcheck findings that `make check` reports when shellcheck is installed.

---

## Dependencies & Execution Order

### Phase Dependencies

- Setup (Phase 1) → Foundational (Phase 2) → US1 (Phase 3) → US2 (Phase 4)
- US3 (Phase 5) and US4 (Phase 6) each need the image from US1; US3's verification tasks (T020, T021) also use the smoke test from US2
- Polish (Phase 7) after all stories

### Within Each User Story

- Guest-side and host-side scripts for the same story are separate files and can be written in parallel; the Makefile wiring comes after both, and the "run it and fix defects" task comes last

### Parallel Opportunities

- T002, T003 after T001
- T005 alongside T004
- T011, T012, T013, T015 together
- T018 and T022 together

## Parallel Example: User Story 2

```text
Task: "Create tests/guest/deny_mkdir.bpf.c"
Task: "Create tests/guest/run.sh"
Task: "Create scripts/ssh-vm.sh"
Task: "Create scripts/run-vm.sh"
```

## Implementation Strategy

### MVP First

Phases 1–3 give a buildable image (US1). Stop and inspect it before going further.

### Incremental Delivery

1. US1: image builds → can already be handed out manually
2. US2: image is proven → safe to publish for Linux attendees
3. US3: OVA + arm64 + docs → macOS and Windows attendees covered
4. US4: `make dist` → repeatable release

## Notes

- Tasks ending in "run … and fix defects" are verification gates, not optional
- macOS and Windows import steps cannot be executed on the Linux build host; T022 must label them
  untested rather than claim they work
