#!/bin/sh
# Start or stop a workshop VM that attendees use over SSH.
#
#   scripts/headless-vm.sh start <amd64|arm64> <disk> <pidfile> <logfile>
#   scripts/headless-vm.sh stop  <amd64|arm64> <disk> <pidfile> <logfile>
set -eu
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

[ $# -eq 5 ] || die "usage: $0 <start|stop> <amd64|arm64> <disk> <pidfile> <logfile>"
action=$1
arch=$2
disk=$3
pidfile=$4
logfile=$5
scripts=$(cd "$(dirname "$0")" && pwd)
port=${SSH_PORT:-2222}
vm_name=bpf-lsm-workshop-$arch

running_pid() {
	[ -s "$pidfile" ] || return 1
	_pid=$(cat "$pidfile")
	case "$_pid" in
	*[!0-9]* | '') rm -f "$pidfile"; return 1 ;;
	esac
	_command=$(ps -p "$_pid" -o command= 2>/dev/null) || {
		rm -f "$pidfile"
		return 1
	}
	case "$_command" in
	*"-name $vm_name"*) echo "$_pid" ;;
	*) rm -f "$pidfile"; return 1 ;;
	esac
}

start_vm() {
	need "$(qemu_bin "$arch")" python3 ssh ps
	[ -f "$disk" ] || die "disk image not found: $disk"
	if _pid=$(running_pid); then
		die "the $arch VM is already running as process $_pid; use 'make ssh' or 'make stop'"
	fi

	mkdir -p "$(dirname "$pidfile")" "$(dirname "$logfile")"
	rm -f "$pidfile" "$logfile"
	run_qemu "$arch" \
		-name "$vm_name" -daemonize -pidfile "$pidfile" \
		-serial "file:$logfile" \
		-drive "file=$disk,if=virtio,discard=unmap" \
		-nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$port-:22"

	cleanup=1
	cleanup_start() {
		if [ "$cleanup" = 1 ] && _pid=$(running_pid); then
			kill "$_pid" 2>/dev/null || true
		fi
		[ "$cleanup" = 1 ] && rm -f "$pidfile"
	}
	trap 'cleanup_start; exit 130' HUP INT TERM

	_pid=$(running_pid) || die "QEMU did not create a running VM; see $logfile"
	if [ "$(qemu_accel "$arch")" = tcg ]; then
		boot_wait=${BOOT_TIMEOUT:-1800}
	else
		boot_wait=${BOOT_TIMEOUT:-180}
	fi
	echo "started $vm_name as process $_pid; waiting up to ${boot_wait}s for SSH"
	_start=$(date +%s)
	until "$scripts/ssh-vm.sh" true 2>/dev/null; do
		if ! running_pid >/dev/null; then
			cleanup=0
			die "QEMU exited while the guest booted; see $logfile"
		fi
		if [ "$(($(date +%s) - _start))" -ge "$boot_wait" ]; then
			cleanup_start
			cleanup=0
			die "the guest did not accept SSH within ${boot_wait}s; see $logfile"
		fi
		sleep 2
	done
	cleanup=0
	trap - HUP INT TERM
	echo "SSH is ready on 127.0.0.1:$port; run 'make ssh'"
}

stop_vm() {
	need ps
	if ! _pid=$(running_pid); then
		echo "the $arch VM is not running"
		return
	fi

	echo "stopping $vm_name (process $_pid)"
	if ! "$scripts/ssh-vm.sh" sudo poweroff >/dev/null 2>&1; then
		kill "$_pid" 2>/dev/null || true
	fi
	_tries=0
	while running_pid >/dev/null; do
		_tries=$((_tries + 1))
		if [ "$_tries" -ge 30 ]; then
			kill "$_pid" 2>/dev/null || true
		fi
		if [ "$_tries" -ge 40 ]; then
			kill -KILL "$_pid" 2>/dev/null || true
			break
		fi
		sleep 1
	done
	rm -f "$pidfile"
	echo "stopped $vm_name"
}

case "$action" in
start) start_vm ;;
stop) stop_vm ;;
*) die "action must be start or stop" ;;
esac
