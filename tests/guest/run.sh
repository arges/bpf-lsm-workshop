#!/bin/sh
# Runs inside the workshop VM as the workshop user (see tests/smoke-test.sh).
# Builds a BPF LSM program and its loader, checks that it denies what it
# should while loaded, and checks the rest of the toolchain.
set -eu
cd "$(dirname "$0")"

fail() {
	echo "SMOKE-TEST-FAIL: $*" >&2
	exit 1
}

tr ',' '\n' </sys/kernel/security/lsm | grep -qx bpf ||
	fail "bpf is not an active LSM: $(cat /sys/kernel/security/lsm)"
sudo -n true || fail "password-less sudo does not work"
[ "$(hostname)" = bpf-lsm-workshop ] || fail "unexpected hostname: $(hostname)"

bpftool version | grep -Eq 'features:.*(libbfd|llvm)' ||
	fail "bpftool has no JIT disassembly backend"

labs=$HOME/bpf-lsm-workshop/labs
[ -f "$labs/README.md" ] || fail "the workshop labs are not installed in $labs"
[ -f "$labs/05-copyfail-guard/copyfail_guard.bpf.c" ] ||
	fail "the final lab snapshot is incomplete"
[ ! -e "$labs/vmlinux.h" ] || fail "the image contains a generated vmlinux.h"

echo "building with clang, bpftool and gcc ($(uname -r))"
make clean >/dev/null
make

loader_pid=
stop_loader() {
	[ -z "$loader_pid" ] || sudo kill "$loader_pid" 2>/dev/null || true
	loader_pid=
}
trap stop_loader EXIT

echo "loading and attaching"
# The log belongs to this user on purpose, so the redirect stays outside sudo.
# shellcheck disable=SC2024
sudo ./deny_mkdir >loader.log 2>&1 &
loader_pid=$!
# Attaching can take several seconds on a slow or busy host.
tries=0
until grep -qx attached loader.log; do
	tries=$((tries + 1))
	if [ "$tries" -ge 120 ] || ! kill -0 "$loader_pid" 2>/dev/null; then
		cat loader.log >&2
		fail "the loader did not attach the program"
	fi
	sleep 0.5
done
sudo bpftool prog show name deny_mkdir | grep -q lsm || fail "program is not loaded as an LSM program"
sudo bpftool prog dump jited name deny_mkdir opcodes |
	grep -Eq '^[[:space:]]*[[:xdigit:]]+:' ||
	fail "bpftool could not disassemble the JIT-compiled LSM program"

rm -rf scratch
mkdir scratch
mkdir scratch/allowed || fail "an unrelated mkdir was denied"
if err=$(mkdir scratch/bpf-lsm-denied 2>&1); then
	fail "mkdir of the denied name succeeded while the program was attached"
fi
case "$err" in
*"Operation not permitted"*) echo "denied as expected: $err" ;;
*) fail "mkdir failed for the wrong reason: $err" ;;
esac

echo "unloading"
stop_loader
tries=0
until mkdir scratch/bpf-lsm-denied 2>/dev/null; do
	tries=$((tries + 1))
	[ "$tries" -lt 10 ] || fail "mkdir still denied after the loader exited"
	sleep 1
done

echo "checking bpftrace"
out=$(sudo bpftrace -e 'BEGIN { printf("bpftrace-ok\n"); exit(); }') || fail "bpftrace could not run a program"
case "$out" in
*bpftrace-ok*) ;;
*) fail "unexpected bpftrace output: $out" ;;
esac
sudo bpftrace -l 'fentry:security_inode_mkdir' | grep -q security_inode_mkdir ||
	fail "bpftrace cannot see kernel functions through BTF"

echo "checking gcc with LTO and sanitizers"
printf '#include <stdio.h>\nint main(void) { puts("gcc-ok"); return 0; }\n' >hello.c
gcc -O2 -flto -fsanitize=address,undefined hello.c -o hello || fail "gcc -flto -fsanitize failed"
[ "$(./hello)" = gcc-ok ] || fail "the gcc-built program did not run"

echo SMOKE-TEST-PASS
