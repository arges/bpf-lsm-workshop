# Implementation Plan: Lab Progression

**Branch**: `002-lab-progression` | **Date**: 2026-10-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/002-lab-progression/spec.md`

## Summary

Five directories under `labs/`, each a complete BPF LSM program on the `socket_bind` hook, moving
from "hello" to a deployable Copy Fail mitigation. Labs 01–04 share build and load rules and are
loaded with `bpftool`; lab 05 adds a libbpf-skeleton loader. A trigger tool exercises the hook,
and `labs/test.sh` verifies every lab inside the VM as part of `make test`. See
[research.md](research.md).

## Technical Context

**Language/Version**: C (BPF programs compiled with clang 19; user-space with gcc 14), GNU Make,
POSIX `sh` for the test

**Primary Dependencies**: libbpf 1.5, bpftool 7.5, kernel BTF — all already in the workshop image

**Storage**: N/A

**Testing**: `labs/test.sh`, run in the guest by `tests/smoke-test.sh` (`make test`)

**Target Platform**: the workshop VM (Debian 13, kernel 6.12, amd64 and arm64)

**Project Type**: teaching material (source directories + READMEs)

**Performance Goals**: N/A

**Constraints**: labs 01–04 kernel-side source short enough for slides; no exploit code; no new
packages in the image

**Scale/Scope**: 5 labs, 1 helper tool, 1 test script

## Constitution Check

| Principle | Status | Notes |
|---|---|---|
| I. Recipes, Not Artifacts | PASS | Source and text only; build products git-ignored |
| II. Pinned, Verified Inputs | PASS | No new external inputs |
| III. Runs Where Attendees Are | PASS | Labs run inside the VM, so host OS is irrelevant; tested on both architectures |
| IV. Proven by Booting | PASS | `make test` builds and exercises every lab in the booted image |
| V. Small Surface, Few Dependencies | PASS | Uses only tools already in the image |
| Workshop Safety Constraints | PASS | No exploit code; every denial is removed by unload or reboot |

Post-design re-check: unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/002-lab-progression/
├── spec.md
├── plan.md
├── research.md
├── quickstart.md
├── checklists/requirements.md
└── tasks.md
```

No `data-model.md` or `contracts/`: the feature stores no data and exposes no interface beyond
the per-lab `make` targets documented in `labs/README.md`.

### Source Code (repository root)

```text
labs/
├── README.md                  # overview, Copy Fail background, how to use the labs
├── common.mk                  # shared rules: vmlinux.h, build, load, unload, trace
├── test.sh                    # guest-side test of all labs
├── tools/
│   ├── Makefile
│   └── try-bind.c             # socket() + bind() with chosen family / type / name
├── 01-hello-lsm/              # hello_lsm.bpf.c
├── 02-observe/                # show_bind.bpf.c
├── 03-deny-comm/              # deny_comm.bpf.c
├── 04-deny-af-alg/            # deny_af_alg.bpf.c
└── 05-copyfail-guard/         # copyfail_guard.bpf.c, copyfail_guard.c, copyfail_guard.h
```

Each lab directory also has a `Makefile` and a `README.md`.

**Structure Decision**: One directory per step so attendees can diff neighbours. Shared build
rules live in `labs/common.mk` so each lab's Makefile is two lines and the lab source is the
only thing that differs.

## Complexity Tracking

No constitution violations.
