# BPF-LSM Workshop Constitution

## Core Principles

### I. Recipes, Not Artifacts

The repository MUST contain only what is needed to download inputs and construct the workshop
environment: Makefiles, scripts, small text configuration, tests, and documentation. Built images,
downloaded base images, and other generated binaries MUST NOT be committed; they live in
git-ignored directories and are published as GitHub release assets.

Rationale: the repo stays small and reviewable, and every byte of a released image can be traced
to a line of text someone can read.

### II. Pinned, Verified Inputs

Every external input that ends up inside an image (base OS image, anything fetched by URL) MUST be
pinned to an immutable version and verified against a checksum recorded in the repository before
use. "latest" URLs MUST NOT be used by default targets. Changing a pin is a reviewed change.

Rationale: an attendee's VM and the presenter's VM must behave the same, and a rebuild a week
before the talk must not silently pick up a different kernel.

### III. Runs Where Attendees Are

Linux hosts are the primary target. macOS (Intel and Apple silicon) and Windows hosts MUST each
have a documented, working path to run the released image. One canonical image format is built;
other hypervisor formats are derived from it by an automated conversion, never maintained by hand.
Any platform path that has not actually been exercised MUST be labelled as untested in the docs.

Rationale: the workshop is 80 minutes; nobody should spend it fighting a hypervisor.

### IV. Proven by Booting

An image is not done until an automated test has booted the finished artifact and, inside it,
compiled, loaded, and observed the effect of a BPF LSM program. Build steps MUST fail loudly
(non-zero exit) rather than produce a plausible-looking but unprovisioned image.

Rationale: "BPF LSM is not in the active LSM list" is a failure that only shows up at runtime, and
the worst time to discover it is in front of an audience.

### V. Small Surface, Few Dependencies

Tooling is Make plus POSIX-ish shell, with QEMU as the single required virtualization dependency
on the build host. Builds MUST NOT require root on the build host. New host dependencies, new
languages, and new abstraction layers require a stated reason in the feature plan. The guest image
contains what the workshop needs and nothing speculative.

Rationale: contributors and attendees should be able to read the whole build in one sitting, and
a smaller image downloads faster over conference Wi-Fi.

## Workshop Safety Constraints

- The image ships with publicly documented credentials and passwordless sudo. Documentation MUST
  state that it is a disposable teaching VM and MUST NOT be exposed to untrusted networks.
- Default run configurations MUST use user-mode (NAT) networking and bind any forwarded port to
  the host loopback address only.
- Images MUST NOT contain secrets, personal data, or per-build identity that should be unique per
  machine (SSH host keys, machine-id); these are generated on first boot.
- Workshop exercises that deny operations system-wide MUST be recoverable by rebooting the VM.

## Development Workflow

- Features follow the Spec Kit flow: specification → plan → tasks → implementation, with artifacts
  kept under `specs/`.
- Shell scripts MUST pass `shellcheck` when it is available and MUST use `set -eu`.
- A change that affects image contents is complete only after `make test` passes against a freshly
  built image for at least the amd64 architecture.
- User-facing documentation (README, run instructions) is updated in the same change as the
  behaviour it describes.
- User-facing documentation (README files and `docs/`) MUST be written in plain English for
  readers who are not native English speakers, following the "STE-flavored" mode of the vendored
  ASD-STE100 skill in `.claude/skills/asd-ste100/`: short sentences, active voice, simple tenses,
  no semicolons, one term for one thing. `make check` MUST report no hard findings for these files.

## Governance

This constitution takes precedence over other project conventions. Amendments are made by pull
request that edits this file, states the reason, and bumps the version: MAJOR for removing or
redefining a principle, MINOR for adding a principle or materially expanding guidance, PATCH for
clarifications. Feature plans MUST include a Constitution Check, and any deviation MUST be recorded
with its justification in the plan's Complexity Tracking table.

**Version**: 1.1.0 | **Ratified**: 2026-10-08 | **Last Amended**: 2026-10-14
