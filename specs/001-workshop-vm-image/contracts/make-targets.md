# Contract: Makefile Interface

The Makefile is the project's public interface. Targets exit 0 on success and non-zero on failure.

## Variables

| Variable | Default | Meaning |
|---|---|---|
| `ARCH` | host architecture (`amd64` or `arm64`) | Guest architecture to build/run/test |
| `DISK_SIZE` | `8G` | Virtual disk size of the workshop image |
| `MEM` | `2048` | Guest RAM in MiB for build/run/test |
| `CPUS` | `2` | Guest vCPUs for build/run/test |
| `SSH_PORT` | `2222` | Host loopback port forwarded to guest port 22 (`start`, `run`, `ssh`) |
| `BUILD_TIMEOUT` | `1800` with hardware acceleration, `14400` without | Seconds before a build is aborted |
| `FORMAT` | (none) | Target format for `convert`: `vhdx`, `vdi`, `vmdk`, or `raw` |
| `AAVMF_CODE` | auto-detected | Path to AArch64 UEFI firmware (arm64 only) |

## Targets

| Target | Produces | Notes |
|---|---|---|
| `help` (default) | — | Lists targets and variables |
| `fetch` | `cache/debian-13-generic-$(ARCH)-<serial>.qcow2` | Fails on checksum mismatch; partial downloads are never left under the final name |
| `image` | `build/bpf-lsm-workshop-$(ARCH).qcow2` and `.packages.txt` | Up to date if inputs are unchanged |
| `test` | — | Boots the image read-only and runs the BPF LSM smoke test; prints `SMOKE-TEST-PASS` |
| `run` | `build/run-$(ARCH).qcow2` (overlay, on first use) | Serial console on the terminal; SSH on `127.0.0.1:$(SSH_PORT)`; the workshop image itself is not modified |
| `start` | `build/run-$(ARCH).qcow2`, `.pid`, and `.log` | Starts QEMU in the background and waits for SSH |
| `stop` | — | Gracefully shuts down a VM started with `start`; stops QEMU directly if SSH is unavailable |
| `ssh` | — | Opens an SSH session to a VM started with `start` or `run` |
| `ova` | `build/bpf-lsm-workshop-amd64.ova` | amd64 only |
| `utm` | `build/bpf-lsm-workshop-arm64.utm.zip` | arm64 only (`ARCH=arm64`); a UTM VM bundle for Apple silicon Macs |
| `convert FORMAT=<f>` | `build/bpf-lsm-workshop-$(ARCH).<f>` | Thin wrapper over `qemu-img convert` |
| `dist` | `dist/*` and `dist/SHA256SUMS` | Copies whatever images exist in `build/`; fails if any file is ≥ 2 GiB |
| `check` | — | `shellcheck` over all scripts (skipped with a notice if not installed) |
| `clean` | — | Removes `build/` and `dist/` |
| `distclean` | — | `clean` plus `cache/` |

## Guest contract (what attendees may rely on)

| Item | Value |
|---|---|
| User / password | `workshop` / `workshop`, password-less `sudo` |
| Hostname | `bpf-lsm-workshop` |
| SSH | enabled, password authentication allowed |
| Active LSMs | include `bpf` |
| Tools on `PATH` | `clang`, `llvm-objdump`, `llvm-strip`, `bpftool`, `bpftrace`, `gcc`, `make`, `git`, `vim`, `nano`, `strace`, `tmux`, `curl` (no `g++`) |
| Headers | `<bpf/bpf_helpers.h>` etc. (libbpf); kernel BTF at `/sys/kernel/btf/vmlinux` |
