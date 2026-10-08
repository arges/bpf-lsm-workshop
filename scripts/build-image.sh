#!/bin/sh
# Build the workshop image for one architecture.
#
# Boots the pinned Debian cloud image once on a throwaway overlay, lets
# cloud-init run scripts/provision.sh (served to the guest over HTTP from this
# host), and compresses the result. Needs no root privileges.
set -eu
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

[ $# -eq 3 ] || die "usage: $0 <amd64|arm64> <base-image> <output.qcow2>"
arch=$1
base=$2
out=$3

need qemu-img python3 curl timeout tar sha256sum "$(qemu_bin "$arch")"
[ -f "$base" ] || die "base image not found: $base"

scripts=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$scripts/.." && pwd)
base=$(cd "$(dirname "$base")" && pwd)/$(basename "$base")
mkdir -p "$(dirname "$out")"
outdir=$(cd "$(dirname "$out")" && pwd)
out=$outdir/$(basename "$out")
work=$outdir/work-$arch
log=$outdir/build-$arch.log

accel=$(qemu_accel "$arch")
if [ "$accel" = tcg ]; then
	timeout=${BUILD_TIMEOUT:-14400}
	echo "note: no hardware virtualization for $arch on this host; emulating (slow)"
else
	timeout=${BUILD_TIMEOUT:-1800}
fi

http_pid=
cleanup() {
	[ -z "$http_pid" ] || kill "$http_pid" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM

rm -rf "$work" "$out.tmp"
mkdir -p "$work/seed"

# Package only source material. Generated objects and participant work must
# never leak from the build checkout into the released image.
tar -C "$root" \
	--exclude='labs/work' --exclude='labs/work-*' \
	--exclude='labs/vmlinux.h' --exclude='*.bpf.o' --exclude='*.skel.h' \
	--exclude='labs/tools/try-bind' --exclude='labs/tools/trusted-app' \
	--exclude='labs/tools/fake' --exclude='labs/05-copyfail-guard/copyfail_guard' \
	--exclude='labs/*.log' \
	-czf "$work/seed/labs.tar.gz" labs
labs_sha256=$(sha256sum "$work/seed/labs.tar.gz" | cut -d' ' -f1)
port=$(free_port)

# cloud-init NoCloud seed. vendor-data and network-config are served only so
# that cloud-init does not spend 10 seconds retrying each of them.
sed \
	-e "s|@LABS_URL@|http://10.0.2.2:$port/labs.tar.gz|" \
	-e "s|@LABS_SHA256@|$labs_sha256|" \
	"$scripts/provision.sh" >"$work/seed/user-data"
printf 'instance-id: bpf-lsm-workshop-build\nlocal-hostname: bpf-lsm-workshop\n' >"$work/seed/meta-data"
: >"$work/seed/vendor-data"
cat >"$work/seed/network-config" <<'NETCFG'
version: 2
ethernets:
  nics:
    match:
      name: "e*"
    dhcp4: true
NETCFG

python3 -m http.server "$port" --bind 127.0.0.1 --directory "$work/seed" >"$work/http.log" 2>&1 &
http_pid=$!
tries=0
until curl --silent --fail --output /dev/null "http://127.0.0.1:$port/meta-data"; do
	tries=$((tries + 1))
	[ "$tries" -lt 50 ] || die "seed HTTP server did not start; see $work/http.log"
	sleep 0.1
done

qemu-img create -q -f qcow2 -F qcow2 -b "$base" "$work/disk.qcow2" "${DISK_SIZE:-8G}"

echo "provisioning $arch guest with $accel (timeout ${timeout}s)"
echo "  watch progress with: tail -f $work/serial.log"
# 10.0.2.2 is the host as seen from QEMU's user-mode network.
QEMU_TIMEOUT=$timeout run_qemu "$arch" \
	-no-reboot \
	-serial "file:$work/serial.log" \
	-drive "file=$work/disk.qcow2,if=virtio,format=qcow2,discard=unmap" \
	-nic user,model=virtio-net-pci \
	-smbios "type=1,serial=ds=nocloud;s=http://10.0.2.2:$port/" ||
	die "QEMU failed or timed out after ${timeout}s; see $work/serial.log"

tr -d '\r' <"$work/serial.log" >"$log"
if ! grep -qx 'WORKSHOP-PROVISION-OK' "$log"; then
	echo "---- last lines of $log ----" >&2
	tail -n 40 "$log" >&2
	die "provisioning did not complete; full console log: $log"
fi

sed -n '/^WORKSHOP-PACKAGES-BEGIN$/,/^WORKSHOP-PACKAGES-END$/p' "$log" |
	grep -v '^WORKSHOP-PACKAGES-' >"${out%.qcow2}.packages.txt"

echo "compressing image"
qemu-img convert -c -O qcow2 "$work/disk.qcow2" "$out.tmp"
mv "$out.tmp" "$out"
rm -rf "$work"

echo "built $out ($(du -h "$out" | cut -f1))"
