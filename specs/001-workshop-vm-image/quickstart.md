# Quickstart: Validating the Workshop VM Image

Prerequisites (Linux build host): `make`, `qemu-system-x86_64`, `qemu-img`, `curl`, `python3`,
`ssh`, read/write access to `/dev/kvm`. See [contracts/make-targets.md](contracts/make-targets.md)
for every target and variable.

## 1. Build (User Story 1)

```sh
make image
```

Expected: ends with the path `build/bpf-lsm-workshop-amd64.qcow2`; `qemu-img info` on it shows
`file format: qcow2`, `virtual size: 8 GiB`, and no backing file. Running `make image` again
prints that nothing needs to be done.

Failure check: edit one hex digit of `BASE_SHA512_amd64` in `versions.mk`, remove the file in
`cache/`, run `make image`; it must fail with a checksum error and create nothing in `build/`.
Revert the edit afterwards.

## 2. Prove it (User Story 2)

```sh
make test
```

Expected: last line is `SMOKE-TEST-PASS`, exit status 0.

Interactive check:

```sh
make run          # terminal 1: login workshop / workshop; quit with Ctrl-a x
make ssh          # terminal 2
```

Inside the guest: `cat /sys/kernel/security/lsm` contains `bpf`; `clang --version` and
`bpftool version` work; `sudo -n true` succeeds.

## 3. Other formats (User Story 3)

```sh
make ova
make convert FORMAT=vhdx
make image ARCH=arm64 && make test ARCH=arm64     # slow on an x86 host
```

Expected: `build/bpf-lsm-workshop-amd64.ova`, `…-amd64.vhdx`, and `…-arm64.qcow2` exist. Importing
the OVA into VirtualBox or VMware and logging in is a manual check; see `docs/running.md`.

## 4. Release bundle (User Story 4)

```sh
make dist
(cd dist && sha256sum -c SHA256SUMS)
```

Expected: every line `OK`; no file in `dist/` is 2 GiB or larger.
