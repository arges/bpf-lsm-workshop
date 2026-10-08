# Research: Lab Progression

## R1. What Copy Fail needs, and where to stop it

- **Facts**: CVE-2026-31431 is a logic bug in the `authencesn` AEAD template reachable through
  `algif_aead`, giving an unprivileged user a 4-byte write into the page cache of any readable
  file. The exploit creates an `AF_ALG` socket, binds it to an AEAD algorithm, sets a key,
  accepts a request socket, then uses `splice()`, `sendmsg()` and `recvmsg()`.
  ([Help Net Security](https://www.helpnetsecurity.com/2026/04/30/copyfail-linux-lpe-vulnerability-cve-2026-31431/),
  [Cloudflare](https://blog.cloudflare.com/copy-fail-linux-vulnerability-mitigation/))
- **Decision**: Hook `socket_bind` and deny binding an `AF_ALG` address of type `aead`.
- **Rationale**: It is the approach Cloudflare describes for its own fleet (deny `socket_bind`
  for `AF_ALG` unless the calling binary is on an allow list, after first measuring who uses
  `AF_ALG`). The hook receives the address, so the labs can progress from "who called" to
  "which family" to "which algorithm type" on one hook.
- **Alternatives considered**:
  - `socket_create`, denying `AF_ALG` sockets outright (used by
    [cozystack/copy-fail-blocker](https://github.com/cozystack/copy-fail-blocker)): simpler, but
    its arguments are three integers, which leaves nothing to teach about reading structured
    arguments, and it cannot tell AEAD from hashing.
  - Hooking `splice`-related file hooks: far more traffic and no clean signal.

## R2. One hook for all five labs

- **Decision**: Every lab attaches to `lsm/socket_bind`.
- **Rationale**: The diff between consecutive labs is then only the policy. `bind()` is rare
  enough that trace output stays readable, and easy to trigger on demand.

## R3. Loading

- **Decision**: Labs 01–04 are loaded with `bpftool prog load … autoattach` through a shared
  `labs/common.mk`; lab 05 has its own libbpf-skeleton loader.
- **Rationale**: Attendees write no user-space code until the lab that needs it (allow list map,
  mode switch, ring buffer). `autoattach` pins the link, so `rm` of the pin detaches.

## R4. Identifying allowed programs

- **Decision**: Lab 04 compares `comm`; lab 05 keys a hash map on the executable's device and
  inode numbers (`task->mm->exe_file->f_inode`), filled by the loader from `stat()`.
- **Rationale**: `comm` is set by the process itself, which lab 04's README has attendees
  demonstrate. Cloudflare's version checks the binary path; resolving a path inside a
  non-sleepable LSM hook is awkward, and device + inode gives the same unforgeable-by-rename
  property in a few lines.
- **Limits recorded in the lab README**: file identity is not content identity; `st_dev` and the
  kernel's `s_dev` disagree on overlayfs and btrfs subvolumes.

## R5. Demonstrating without an exploit

- **Decision**: `labs/tools/try-bind` performs `socket()` + `bind()` for `AF_INET` or `AF_ALG`
  with a chosen type and name, and reports the result.
- **Rationale**: The VM kernel (6.12.111) is patched, and shipping an exploit would be
  inappropriate. The first two steps are harmless and are exactly what the mitigation gates.
- **(measured)** An unprivileged `bind()` to `authencesn(hmac(sha256),cbc(aes))` succeeds in the
  VM with no program loaded, so the needed crypto modules survived the image's module pruning.

## R6. Verifier behaviour worth teaching

- **(measured)** On kernel 6.12 the verifier requires an LSM program's return value to be
  provably within `[-4095, 0]`. Clang compiles `flag ? -EPERM : 0` into a negation of the flag,
  which the verifier rejects as an unknown scalar. Hit twice while writing this project.
- **Decision**: Labs 03 and 04 return constants on separate branches, which compiles cleanly;
  lab 05 computes the verdict from two flags and uses `barrier_var()` with a comment explaining
  why.
- **(measured)** `bpf_strncmp()` needs its constant string in read-only data at a fixed address,
  so the allow list in lab 04 is separate named constants rather than an array indexed in a
  loop.
