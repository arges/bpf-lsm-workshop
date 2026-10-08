#!/bin/sh
# Boot a workshop image and run tests/guest/run.sh and labs/test.sh inside it.
#
#   tests/smoke-test.sh <amd64|arm64> <disk-image>
#
# The image is opened with -snapshot, so it is never modified. The VM gets a
# different MAC address from the one used at build time to prove the image
# does not depend on it. Set HW=legacy (amd64 only) to boot with an IDE disk
# and an e1000 NIC, the hardware described by the OVA.
set -eu
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/../scripts/lib.sh"

[ $# -eq 2 ] || die "usage: $0 <amd64|arm64> <disk-image>"
arch=$1
image=$2

need python3 ssh tar "$(qemu_bin "$arch")"
[ -f "$image" ] || die "image not found: $image"
root=$(cd "$(dirname "$0")/.." && pwd)

case "${HW:-virtio}" in
virtio)
	disk_if=virtio
	nic=virtio-net-pci
	;;
legacy)
	[ "$arch" = amd64 ] || die "HW=legacy is only supported for amd64"
	# shellcheck disable=SC2034  # read by run_qemu in scripts/lib.sh
	QEMU_MACHINE=pc
	disk_if=ide
	nic=e1000
	;;
*) die "HW must be virtio or legacy" ;;
esac

if [ "$(qemu_accel "$arch")" = tcg ]; then
	boot_wait=${BOOT_TIMEOUT:-1800}
else
	boot_wait=${BOOT_TIMEOUT:-180}
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/bpf-lsm-smoke.XXXXXX")
status=1
cleanup() {
	if [ -f "$work/qemu.pid" ]; then
		kill "$(cat "$work/qemu.pid")" 2>/dev/null || true
	fi
	if [ "$status" -ne 0 ] && [ -f "$work/serial.log" ]; then
		echo "---- last lines of the guest console ----" >&2
		tail -n 30 "$work/serial.log" | tr -d '\r' >&2
	fi
	rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

SSH_PORT=$(free_port)
export SSH_PORT

echo "booting $image ($arch, $(qemu_accel "$arch"), ${HW:-virtio} hardware)"
run_qemu "$arch" \
	-snapshot -daemonize -pidfile "$work/qemu.pid" \
	-serial "file:$work/serial.log" \
	-drive "file=$image,if=$disk_if" \
	-nic "user,model=$nic,mac=52:54:00:ab:cd:ef,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22"

echo "waiting up to ${boot_wait}s for ssh"
start=$(date +%s)
until "$root/scripts/ssh-vm.sh" true 2>/dev/null; do
	kill -0 "$(cat "$work/qemu.pid")" 2>/dev/null || die "QEMU exited before the guest came up"
	[ $(($(date +%s) - start)) -lt "$boot_wait" ] || die "guest did not accept ssh logins within ${boot_wait}s"
	sleep 2
done
echo "guest is up after $(($(date +%s) - start))s"

tar -C "$root" -cf - tests/guest |
	"$root/scripts/ssh-vm.sh" 'rm -rf smoke && mkdir smoke && tar -C smoke -xf - &&
		sh smoke/tests/guest/run.sh && sh ~/bpf-lsm-workshop/labs/test.sh'
status=0
