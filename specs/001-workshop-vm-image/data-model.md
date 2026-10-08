# Data Model: Workshop VM Image

This feature has no runtime data store. The "entities" are files and the pins that identify them.

## Base image pin (`versions.mk`)

| Field | Example | Rule |
|---|---|---|
| `DEBIAN_VERSION` / `DEBIAN_RELEASE` | `13` / `trixie` | Stable release only |
| `BASE_SERIAL` | `20261001-2618` | A dated directory on cloud.debian.org, never `latest` |
| `BASE_SHA512_<arch>` | 128 hex chars | Must equal the entry in that directory's `SHA512SUMS` |

Derived: URL
`https://cloud.debian.org/images/cloud/<release>/<serial>/debian-<version>-generic-<arch>-<serial>.qcow2`
and cache path `cache/debian-<version>-generic-<arch>-<serial>.qcow2`.

## Workshop image

| Field | Value |
|---|---|
| Path | `build/bpf-lsm-workshop-<arch>.qcow2` |
| Architecture | `amd64` or `arm64` |
| Format | qcow2 v3, zlib-compressed, no backing file |
| Virtual size | `DISK_SIZE` (default 8G) |
| Companion | `build/bpf-lsm-workshop-<arch>.packages.txt` (installed package versions) |
| Invariants | No SSH host keys; empty `/etc/machine-id`; cloud-init removed; network matched by interface name, not MAC; `bpf` in active LSM list; user `workshop` exists |

State transitions during a build:

```text
(absent) → overlay created → provisioning in guest → marker OK → compressed to *.tmp → renamed
                                   │ marker missing / timeout / non-zero
                                   └────────────→ build fails, no output file
```

## Derived image

| Format | Path | Source |
|---|---|---|
| OVA (amd64) | `build/bpf-lsm-workshop-amd64.ova` | workshop image |
| `vhdx`, `vdi`, `vmdk`, `raw` | `build/bpf-lsm-workshop-<arch>.<format>` | workshop image |

## Release bundle

`dist/` containing each built `*.qcow2`, the amd64 `*.ova` if built, the package manifests, and
`SHA256SUMS` covering every other file in the directory. Each file must be < 2 GiB.
