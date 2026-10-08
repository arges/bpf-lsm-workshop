# Feature Specification: Workshop VM Image

**Feature Branch**: `001-workshop-vm-image` (spec directory; no git branch was created)

**Created**: 2026-10-08

**Status**: Draft

**Input**: User description: "I want a Makefile target that will generate a runnable, minimal VM
image. It should be sufficient for compiling and inserting bpf-lsm modules onto the system so it
needs to have developer tools. Ideally using debian or ubuntu. The VM should be runnable primarily
on a Linux host, but it should also be able to work on OS X and Windows as well. Find a common
image format that works across tools and/or a method to convert. The repo should only contain what
is necessary to download the right items to construct the VM image. We can then host the VM image
on github as a release artifact."

**Context**: The image supports the hands-on workshop "Mitigating All The Vulns with BPF-LSM: A
Tutorial" (Texas Linux Fest 2026, 6 November 2026, 80 minutes). Attendees are told to bring "a
laptop capable of running a provided VM image" and are expected to write, load, and test their own
BPF LSM program during the session.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Maintainer builds the image with one command (Priority: P1)

The workshop maintainer clones the repository on a Linux machine and runs a single Makefile target.
Without any further input, and without needing administrator rights, they end up with a bootable
VM disk image containing a Debian system that has everything needed to compile and load BPF LSM
programs.

**Why this priority**: Nothing else exists without the image. This alone is a usable deliverable:
the maintainer can hand the file to attendees.

**Independent Test**: On a clean checkout, run the build target and confirm that it exits
successfully and produces a single disk image file in the documented output location.

**Acceptance Scenarios**:

1. **Given** a clean checkout on a Linux host with the documented prerequisites, **When** the
   maintainer runs the build target, **Then** the base operating system image is downloaded,
   verified, customised, and a finished image file is produced with no interactive prompts.
2. **Given** a downloaded base image whose contents do not match the checksum recorded in the
   repository, **When** the build target runs, **Then** the build stops with an error naming the
   mismatched file and no finished image is produced.
3. **Given** provisioning fails part-way (for example, a package cannot be installed), **When** the
   build target runs, **Then** it exits non-zero and does not leave a file that looks like a
   finished image.
4. **Given** a previous successful build, **When** the maintainer runs the build target again
   without changing any inputs, **Then** nothing is re-downloaded or rebuilt.

---

### User Story 2 - The image is proven fit for the workshop (Priority: P2)

Before publishing, the maintainer runs a single test target. It boots the finished image, and
inside it compiles a small BPF LSM program, loads it, and confirms that the program actually denies
an operation. An attendee on a Linux laptop can likewise start the image with one command and log
in.

**Why this priority**: An image that boots but cannot load a BPF LSM program (wrong kernel
configuration, missing toolchain piece) would sink the workshop. This is the check that the image
does its one job.

**Independent Test**: Run the test target against a built image; it reports pass or fail and exits
accordingly. Separately, run the "run" target and log in with the documented credentials.

**Acceptance Scenarios**:

1. **Given** a finished image, **When** the test target runs, **Then** the VM boots, a BPF LSM
   program is compiled and loaded inside it, an operation the program targets is denied while
   unrelated operations still succeed, and the target reports success.
2. **Given** a finished image, **When** a user starts it with the run target and logs in with the
   documented credentials, **Then** they have a shell with administrator access and the compiler,
   BPF loader tooling, and kernel type information needed for the workshop exercises.
3. **Given** a finished image started on a different virtual machine than the one that built it
   (different virtual network card address), **When** it boots, **Then** it still obtains network
   access and accepts logins.
4. **Given** a finished image, **When** an attendee logs in without network access, **Then** the
   complete workshop lab snapshots and shared tools are available in
   `~/bpf-lsm-workshop/labs`.

---

### User Story 3 - Attendees on macOS and Windows can run the image (Priority: P3)

An attendee with a Mac (Intel or Apple silicon) or a Windows laptop downloads an image suitable
for their machine and virtualization tool, and gets to the same logged-in shell as a Linux user.

**Why this priority**: Linux hosts are the primary audience, but a conference room will contain
Macs and Windows laptops. Without this, those attendees can only watch.

**Independent Test**: Produce each derived format from the canonical image with one target each,
and import/boot it with the corresponding tool; follow the per-platform instructions on a machine
of that type.

**Acceptance Scenarios**:

1. **Given** a finished canonical image, **When** the maintainer runs a conversion target, **Then**
   an image in the requested hypervisor format is produced from it without rebuilding.
2. **Given** a Mac with Apple silicon, **When** the attendee follows the documented steps with the
   image built for that processor architecture, **Then** the VM runs at native (hardware
   virtualized) speed.
3. **Given** a Windows or macOS host, **When** the attendee follows the documented steps for their
   virtualization tool, **Then** the VM boots to a login prompt and accepts the documented
   credentials.

---

### User Story 4 - Maintainer publishes release files (Priority: P4)

The maintainer runs one target that gathers the images to publish together with a checksum file,
ready to attach to a GitHub release, so attendees can verify their download.

**Why this priority**: Publishing can be done by hand at first; automation here removes a
last-minute error source but is not required for the image to exist.

**Independent Test**: Run the packaging target and confirm the output directory contains the image
files and a checksum file whose entries verify.

**Acceptance Scenarios**:

1. **Given** finished images, **When** the packaging target runs, **Then** a directory of
   release-ready files with a checksum manifest is produced, and every file is below the per-file
   size limit for GitHub release assets.

---

### Edge Cases

- The build host has no hardware virtualization available (e.g. a CI runner or a VM without nested
  virtualization): the build must still work, only slower.
- The build is interrupted (Ctrl-C, power loss) mid-download or mid-provisioning: the next run must
  not treat a partial file as complete.
- The guest never finishes provisioning (hangs): the build must time out and fail rather than wait
  forever.
- A port the run/test target wants on the host is already in use: the user gets a clear error and a
  way to choose another port.
- An image built on one processor architecture is requested for another (building the Apple silicon
  image on an Intel/AMD Linux host): supported, with the understanding that it is slow.
- Two VMs started from copies of the same released image on the same network must not share
  machine identity (host keys, machine ID).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The repository MUST provide a single Makefile target that produces a bootable VM disk
  image from a clean checkout with no interactive input.
- **FR-002**: The guest operating system MUST be a current stable Debian or Ubuntu release.
- **FR-003**: The build MUST obtain the base operating system by downloading a pinned, published
  image and MUST verify it against a checksum stored in the repository before using it.
- **FR-004**: The repository MUST NOT contain built images, downloaded images, or other large
  binaries; all such files MUST be created in ignored working directories.
- **FR-005**: The build MUST NOT require administrator (root) privileges on the build host.
- **FR-006**: The image MUST have the BPF LSM enabled in the running kernel at boot, with no manual
  step by the attendee.
- **FR-007**: The image MUST contain the tools required to write, compile, load, inspect, and
  remove BPF LSM programs: a C compiler able to target BPF, the BPF library headers, a BPF
  load/inspect utility, kernel type information, standard build tools, a text editor, and source
  control.
- **FR-008**: The image MUST provide a documented user account with a documented password and
  password-less administrator access, reachable both on the VM console and over SSH.
- **FR-009**: The image MUST NOT depend on the identity of the virtual hardware it was built on;
  networking and login MUST work when started under a different hypervisor or with a different
  network card address.
- **FR-010**: Per-machine identity (SSH host keys, machine ID) MUST NOT be baked into the image and
  MUST be generated on first boot.
- **FR-011**: The build MUST fail with a non-zero exit status, and leave no finished-looking image,
  when the download, checksum verification, or in-guest provisioning fails or times out.
- **FR-012**: The repository MUST provide a target that boots a built image on a Linux or macOS
  host for interactive use.
- **FR-013**: The repository MUST provide an automated test target that boots a built image and
  verifies, inside it, that a BPF LSM program can be compiled, loaded, and observed denying an
  operation.
- **FR-014**: The canonical image MUST be in one widely supported disk format, and the repository
  MUST provide targets that convert it to the formats needed by the other mainstream desktop
  virtualization tools on Linux, macOS, and Windows.
- **FR-015**: Images MUST be buildable for both 64-bit Intel/AMD and 64-bit ARM processors, so
  Apple silicon Macs can run the workshop at native speed.
- **FR-016**: The repository MUST document, per host platform (Linux, macOS, Windows), how to run
  the released image, and MUST mark any path that has not been exercised as untested.
- **FR-017**: The repository MUST provide a target that assembles release-ready files and a
  checksum manifest for attaching to a GitHub release.
- **FR-018**: Each finished image file MUST be smaller than 2 GiB so it can be published as a
  single GitHub release asset.
- **FR-019**: Default run configurations MUST keep the VM off the host's LAN (NAT only) and expose
  its SSH service only on the host's loopback address.
- **FR-020**: The image MUST contain the workshop lab snapshots, shared build rules and trigger
  tools under the workshop user's home directory. Attendees MUST NOT need network access or a
  host-to-guest file transfer to begin the labs.

### Key Entities

- **Base image**: the upstream distribution's published cloud image for one processor architecture;
  identified by release, build serial, architecture, and checksum.
- **Workshop image**: the finished, customised, compressed disk image in the canonical format; one
  per processor architecture.
- **Derived image**: a workshop image converted or packaged for a specific virtualization tool.
- **Release bundle**: the set of workshop and derived images plus a checksum manifest.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From a clean checkout on a Linux host with hardware virtualization, the maintainer
  gets a finished image for their own processor architecture in under 15 minutes with one command.
- **SC-002**: The automated test passes on a freshly built image: a BPF LSM program written in C is
  compiled, loaded, and denies its target operation inside the VM.
- **SC-003**: An attendee on a Linux host goes from a downloaded image to a logged-in shell in
  under 2 minutes using only documented commands.
- **SC-004**: Each published image file is under 2 GiB.
- **SC-005**: The repository, excluding ignored build output, stays under 1 MB.
- **SC-006**: Every host platform in scope (Linux, macOS Intel, macOS Apple silicon, Windows) has
  at least one documented way to run the image.

## Assumptions

- **Debian over Ubuntu**: the user accepted either. Debian 13 "trixie" is assumed because it ships
  a recent long-term kernel with BPF LSM built in and publishes small cloud images for both
  processor architectures. Ubuntu remains a possible later variant.
- **Credentials are public**: user `workshop`, password `workshop`. This is a disposable teaching
  VM, not a hardened system.
- **Building is Linux-only**: attendees on macOS and Windows only *run* released images; they are
  not expected to build them. The maintainer builds on Linux.
- **No graphical desktop**: the workshop is command-line only; the image is headless and used via
  console or SSH. Attendees may use their host editor over SSH.
- **Workshop exercise content is out of scope** for this feature: the lab source code, slides, and
  exercises are a separate feature. This feature delivers only the environment and one small
  test program that proves the environment works.
- **Publishing is a manual step**: creating the GitHub release and uploading files is done by the
  maintainer (optionally with the GitHub CLI); automated release pipelines are out of scope here.
- **No secure-boot or kernel-lockdown hardening** is applied; the guest runs the distribution's
  stock signed kernel with default settings.
- **Verification environment**: macOS and Windows paths cannot be exercised on the maintainer's
  Linux build machine and will be documented as untested until someone runs them.
