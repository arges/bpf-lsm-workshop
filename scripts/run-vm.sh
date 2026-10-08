#!/bin/sh
# Boot a workshop image interactively on a Linux or macOS host.
#
#   scripts/run-vm.sh <amd64|arm64> <disk-image>
#
# The serial console is attached to this terminal (quit with Ctrl-a x) and the
# guest's SSH port is forwarded to 127.0.0.1:$SSH_PORT (default 2222). The disk
# image is written to; `make run` passes a copy-on-write overlay.
set -eu
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

[ $# -eq 2 ] || die "usage: $0 <amd64|arm64> <disk-image>"
arch=$1
disk=$2

need "$(qemu_bin "$arch")"
[ -f "$disk" ] || die "disk image not found: $disk"

port=${SSH_PORT:-2222}
echo "Login: workshop / workshop    SSH: ssh -p $port workshop@127.0.0.1    Quit: Ctrl-a x"
run_qemu "$arch" \
	-serial mon:stdio \
	-drive "file=$disk,if=virtio,discard=unmap" \
	-nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$port-:22"
