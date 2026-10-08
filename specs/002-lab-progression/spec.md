# Feature Specification: Lab Progression

**Feature Branch**: `002-lab-progression` (spec directory; no git branch was created)

**Created**: 2026-10-09

**Status**: Draft

**Input**: User description: "I want to create multiple code directories that progress through
creating a bpf lsm program. The goal is building up to block something like copy fail. 01 should
be pure scaffolding just hello lsm. 02 should be adding something that prints the syscall and
comm. 03 should be blocking a comm and syscall. 04 should be blocking a syscall but only if a
parameter matches and allow listing certain comm. And 05 should be the complete mitigation for
copy fail."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Attendee gets a first program running (Priority: P1)

An attendee opens the first lab directory in the workshop VM, builds it with one command, loads
it, and sees evidence that their program ran inside the kernel when an ordinary operation
happened. A second lab shows them who triggered it and with what.

**Why this priority**: Everything else builds on a working build-load-observe loop. An attendee
who gets no further still leaves having run a BPF LSM program.

**Independent Test**: In the VM, build and load lab 01, trigger the operation, and see the hello
message; repeat with lab 02 and see the process name and argument reported.

**Acceptance Scenarios**:

1. **Given** the workshop VM, **When** the attendee builds and loads lab 01 and triggers the
   hooked operation, **Then** a hello message appears in the trace output and the operation
   still succeeds.
2. **Given** lab 02 is loaded, **When** a process performs the hooked operation, **Then** the
   output names the operation, the process name, and a distinguishing argument.
3. **Given** any lab is loaded, **When** the attendee runs the unload command, **Then** the
   program is gone and the system behaves as before.

---

### User Story 2 - Attendee blocks something (Priority: P2)

The attendee moves on to programs that refuse operations: first for one named process, then only
when an argument matches and the process is not on an allow list.

**Why this priority**: Denial is the point of an LSM. These two steps introduce the verdict and
the idea of scoping a policy, without yet being a credible defence.

**Independent Test**: With lab 03 loaded, the named program is refused while others are not. With
lab 04 loaded, the matching operation is refused for an ordinary process and permitted for an
allow-listed one, and non-matching operations are untouched.

**Acceptance Scenarios**:

1. **Given** lab 03 is loaded, **When** the named process attempts the operation, **Then** it
   fails with a permission error, and the same operation by another process succeeds.
2. **Given** lab 04 is loaded, **When** an ordinary process attempts the operation with the
   matching argument, **Then** it is refused; with a non-matching argument it succeeds.
3. **Given** lab 04 is loaded, **When** an allow-listed process attempts the operation with the
   matching argument, **Then** it succeeds.

---

### User Story 3 - Attendee builds a real mitigation (Priority: P3)

The final lab is a mitigation for the Copy Fail vulnerability that the attendee could defend in
a review: it blocks exactly the step the exploit needs, exempts legitimate programs in a way an
attacker cannot forge, can be trialled without blocking anything, and reports what it does.

**Why this priority**: This is the payoff of the talk, and depends on the earlier steps.

**Independent Test**: With lab 05 running, the operation the exploit depends on is refused for an
ordinary program, permitted for a listed program, refused for an impostor using the listed
program's name, and unrelated uses of the same facility keep working; in audit mode nothing is
refused and each would-be denial is reported.

**Acceptance Scenarios**:

1. **Given** lab 05 in enforce mode, **When** an unlisted program performs the exploit's
   prerequisite step, **Then** it is refused and the refusal is reported with the process
   identity.
2. **Given** lab 05 with a program on its allow list, **When** that program performs the same
   step, **Then** it succeeds; **When** a different file with the same name does, **Then** it is
   refused.
3. **Given** lab 05 in enforce mode, **When** a program uses the same kernel facility in a way
   unrelated to the vulnerability, **Then** it succeeds.
4. **Given** lab 05 in audit mode, **When** an unlisted program performs the step, **Then** it
   succeeds and is reported as something that would have been denied.

---

### Edge Cases

- A lab is loaded twice, or unloaded when not loaded: the commands must not leave the system in a
  confusing state.
- A program denies something the attendee needs (for example their own shell's networking): a
  reboot must always recover the VM.
- The compiler optimises a program into a form the kernel verifier rejects although the source
  is correct.
- The VM kernel is already patched against Copy Fail, so the exploit itself cannot be used to
  demonstrate the mitigation.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The repository MUST contain five lab directories, numbered 01 to 05, each complete
  and buildable on its own inside the workshop VM with a single command.
- **FR-002**: Each lab MUST differ from the previous one by a small, nameable set of ideas, and
  all labs MUST use the same kernel hook so that only the decision logic changes.
- **FR-003**: Lab 01 MUST be scaffolding only: a program that attaches, reports that it ran, and
  allows everything.
- **FR-004**: Lab 02 MUST report the operation, the calling process name, and at least one
  argument, without denying anything.
- **FR-005**: Lab 03 MUST deny the operation for one named process and allow it for all others.
- **FR-006**: Lab 04 MUST deny the operation only when an argument matches, and MUST exempt
  processes on an allow list of names.
- **FR-007**: Lab 05 MUST deny exactly the step the Copy Fail exploit requires, MUST leave
  unrelated uses of the same facility working, MUST identify exempt programs in a way a process
  cannot forge by renaming itself, MUST offer a mode that reports without denying, and MUST
  report each decision with the process identity.
- **FR-008**: Each lab MUST provide commands to build, load, observe, and unload, and written
  instructions stating what to run and what to expect.
- **FR-009**: The repository MUST provide a harmless way to trigger the hooked operation with
  chosen arguments. The repository MUST NOT contain exploit code.
- **FR-010**: An automated test MUST build every lab inside the workshop VM and verify the
  behaviour each lab's instructions describe, as part of the existing image test.
- **FR-011**: Every denial introduced by a lab MUST be undone by unloading the program or
  rebooting the VM.

### Key Entities

- **Lab**: a numbered directory with a kernel-side program, build instructions, and a README.
- **Trigger tool**: a small program that performs the hooked operation with chosen arguments.
- **Allow list**: the set of programs exempt from a denial; by name in lab 04, by file identity
  in lab 05.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An attendee can build and load any lab in under one minute using the commands in
  its README.
- **SC-002**: The automated test passes on both image architectures: every lab builds, loads,
  and shows its described behaviour.
- **SC-003**: Each lab's kernel-side source fits on two slides (about 60 lines excluding
  comments) for labs 01–04.
- **SC-004**: With lab 05 enforcing, the exploit's prerequisite step fails for every program not
  on the allow list, including one that copies an allowed program's name.

## Assumptions

- **The hooked operation is binding a socket.** Copy Fail requires binding a kernel crypto API
  socket to an AEAD algorithm, which matches the mitigation Cloudflare described publicly, so
  all five labs hook that one operation.
- **"Prints the syscall" means the hooked operation.** BPF LSM programs attach to security hooks
  rather than system calls; lab 02 reports the hook's operation, and the lab notes explain the
  difference.
- **Labs are complete solutions**, not fill-in-the-blank exercises. Starter versions with gaps
  for attendees to complete can be derived later.
- **No exploit is shipped or needed**: the VM kernel is patched, and the trigger tool performs
  only the first two harmless steps of the attack.
- **Slides and speaker notes are out of scope.**
- **Getting the labs into the VM** (baking them into the image or cloning) is a separate
  decision; the automated test copies them in.
