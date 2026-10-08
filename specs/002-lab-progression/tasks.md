---

description: "Task list for the Lab Progression feature"
---

# Tasks: Lab Progression

**Input**: Design documents from `/specs/002-lab-progression/`

**Prerequisites**: plan.md, spec.md, research.md, quickstart.md

**Tests**: Included; FR-010 requires an automated in-VM test.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup (Shared Infrastructure)

- [X] T001 Create `labs/common.mk` with shared rules: generate `labs/vmlinux.h`, build `$(NAME).bpf.o`, `load` (bpftool autoattach, pinned at `/sys/fs/bpf/$(NAME)`), `unload`, `trace`, `clean`
- [X] T002 [P] Create `labs/tools/try-bind.c` and `labs/tools/Makefile`
- [X] T003 [P] Add lab build products to `.gitignore`

---

## Phase 2: Foundational (Blocking Prerequisites)

- [X] T004 Create `labs/test.sh` skeleton (build everything, `expect_ok` / `expect_denied` helpers, cleanup trap) and call it from `tests/smoke-test.sh` after `tests/guest/run.sh`; include `labs/*.sh` in `make check`

---

## Phase 3: User Story 1 - Attendee gets a first program running (Priority: P1) 🎯 MVP

**Independent Test**: labs 01 and 02 sections of `labs/test.sh`

- [X] T005 [P] [US1] Create `labs/01-hello-lsm/hello_lsm.bpf.c` and `Makefile`: attach to `lsm/socket_bind`, `bpf_printk` a hello, return `ret`
- [X] T006 [P] [US1] Create `labs/02-observe/show_bind.bpf.c` and `Makefile`: print comm, pid and `address->sa_family`
- [X] T007 [US1] Add lab 01 and 02 checks to `labs/test.sh` (trace output contains the expected lines)
- [X] T008 [P] [US1] Write `labs/01-hello-lsm/README.md` and `labs/02-observe/README.md`

---

## Phase 4: User Story 2 - Attendee blocks something (Priority: P2)

**Independent Test**: labs 03 and 04 sections of `labs/test.sh`

- [X] T009 [P] [US2] Create `labs/03-deny-comm/deny_comm.bpf.c` and `Makefile`: `-EPERM` when comm is `nc`
- [X] T010 [P] [US2] Create `labs/04-deny-af-alg/deny_af_alg.bpf.c` and `Makefile`: `-EPERM` for `AF_ALG` addresses unless comm is on the allow list
- [X] T011 [US2] Add lab 03 and 04 checks to `labs/test.sh`
- [X] T012 [P] [US2] Write `labs/03-deny-comm/README.md` and `labs/04-deny-af-alg/README.md`

---

## Phase 5: User Story 3 - Attendee builds a real mitigation (Priority: P3)

**Independent Test**: lab 05 sections of `labs/test.sh`

- [X] T013 [US3] Create `labs/05-copyfail-guard/copyfail_guard.h` (shared `exe_id` and `event` structures)
- [X] T014 [US3] Create `labs/05-copyfail-guard/copyfail_guard.bpf.c`: match `AF_ALG` type `aead`, allow list map keyed on executable device + inode, `enforce` read-only flag, ring buffer events
- [X] T015 [US3] Create `labs/05-copyfail-guard/copyfail_guard.c` and `Makefile`: skeleton loader with `--audit` and `--allow PATH`, event printing
- [X] T016 [US3] Add lab 05 enforce-mode and audit-mode checks to `labs/test.sh`, including the same-name-different-file case
- [X] T017 [P] [US3] Write `labs/05-copyfail-guard/README.md`

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T018 [P] Write `labs/README.md` (overview table, Copy Fail background with sources, usage, hooks versus system calls)
- [X] T019 Update the root `README.md` to describe the labs
- [X] T020 Run `make test` for amd64 and arm64 and fix defects until both print `LABS-TEST-PASS`

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 → US1 → US2 → US3 → Polish
- Each lab's source and README are independent files and can be written in parallel; the
  `labs/test.sh` additions are sequential because they share one file

## Implementation Strategy

Labs 01 and 02 alone are a usable first session. Each later lab is an independent increment that
can be demonstrated on its own.
