# shellcheck shell=sh
# Shared helpers for the host-side scripts. Source this file; do not run it.

die() {
	echo "error: $*" >&2
	exit 1
}

need() {
	for _cmd in "$@"; do
		command -v "$_cmd" >/dev/null 2>&1 || die "required command not found: $_cmd"
	done
}

# Debian architecture name of the machine we are running on.
host_arch() {
	case "$(uname -m)" in
	x86_64 | amd64) echo amd64 ;;
	aarch64 | arm64) echo arm64 ;;
	*) die "unsupported host architecture: $(uname -m)" ;;
	esac
}

qemu_bin() {
	case "$1" in
	amd64) echo qemu-system-x86_64 ;;
	arm64) echo qemu-system-aarch64 ;;
	*) die "unsupported guest architecture: $1 (expected amd64 or arm64)" ;;
	esac
}

# Fastest accelerator usable for guest architecture $1: kvm, hvf, or tcg.
# Hardware virtualization only applies when guest and host architectures match.
qemu_accel() {
	if [ "$1" = "$(host_arch)" ]; then
		case "$(uname -s)" in
		Linux)
			if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
				echo kvm
				return
			fi
			;;
		Darwin)
			if [ "$(sysctl -n kern.hv_support 2>/dev/null)" = 1 ]; then
				echo hvf
				return
			fi
			;;
		esac
	fi
	echo tcg
}

# Path to an AArch64 UEFI firmware image. Override with AAVMF_CODE.
find_aavmf() {
	if [ -n "${AAVMF_CODE:-}" ]; then
		[ -f "$AAVMF_CODE" ] || die "AAVMF_CODE=$AAVMF_CODE does not exist"
		echo "$AAVMF_CODE"
		return
	fi
	for _fw in \
		/usr/share/AAVMF/AAVMF_CODE.fd \
		/usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
		/usr/share/edk2/aarch64/QEMU_EFI.fd \
		/usr/share/qemu/edk2-aarch64-code.fd \
		/opt/homebrew/share/qemu/edk2-aarch64-code.fd \
		/usr/local/share/qemu/edk2-aarch64-code.fd; do
		if [ -f "$_fw" ]; then
			echo "$_fw"
			return
		fi
	done
	die "no AArch64 UEFI firmware found; install AAVMF/edk2 (e.g. qemu-efi-aarch64) or set AAVMF_CODE"
}

# Print a TCP port that is currently free on the loopback interface.
free_port() {
	python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'
}

# run_qemu ARCH [qemu arguments...]
#
# Runs QEMU for the given guest architecture with the machine type, CPU model,
# accelerator, firmware, memory and CPU count filled in. Callers add disks,
# network and console. Honours MEM, CPUS, QEMU_MACHINE (amd64 only) and
# QEMU_TIMEOUT (seconds; QEMU is killed after that long).
run_qemu() {
	_arch=$1
	shift
	_bin=$(qemu_bin "$_arch") || exit 1
	_accel=$(qemu_accel "$_arch") || exit 1
	case "$_arch" in
	amd64)
		_cpu=max
		set -- -machine "${QEMU_MACHINE:-q35}" "$@"
		;;
	arm64)
		# neoverse-n1 rather than "max": pointer authentication makes
		# emulated "max" several times slower for no benefit here.
		_cpu=neoverse-n1
		_fw=$(find_aavmf) || exit 1
		set -- -machine virt -bios "$_fw" "$@"
		;;
	esac
	case "$_accel" in
	tcg) _accel=tcg,thread=multi ;;
	*) _cpu=host ;;
	esac
	set -- "$_bin" -accel "$_accel" -cpu "$_cpu" -m "${MEM:-2048}" -smp "${CPUS:-2}" \
		-display none -device virtio-rng-pci "$@"
	if [ -n "${QEMU_TIMEOUT:-}" ]; then
		set -- timeout "$QEMU_TIMEOUT" "$@"
	fi
	"$@"
}
