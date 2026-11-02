#!/bin/sh
# Builds every lab inside the workshop VM and checks that each one behaves as
# its README says. Run by tests/smoke-test.sh; also runnable by hand.
set -eu
cd "$(dirname "$0")"
labs=$PWD

fail() {
	echo "LABS-TEST-FAIL: $*" >&2
	exit 1
}

try=$labs/tools/try-bind
trusted=$labs/tools/trusted-app
trace=/sys/kernel/tracing/trace
aead='authencesn(hmac(sha256),cbc(aes))'

clear_trace() { sudo sh -c ": >$trace"; }
traced() { sudo grep -q "$1" "$trace"; }

# expect_ok / expect_denied <command...>: run a try-bind style command and
# check that bind() succeeded, or failed with EPERM specifically.
expect_ok() {
	out=$("$@" 2>&1) || fail "expected success: $* -> $out"
}
expect_denied() {
	if out=$("$@" 2>&1); then
		fail "expected a denial: $* -> $out"
	fi
	case "$out" in
	*"Operation not permitted"*) ;;
	*) fail "failed for the wrong reason: $* -> $out" ;;
	esac
}

guard_pid=
cleanup() {
	[ -z "$guard_pid" ] || sudo kill "$guard_pid" 2>/dev/null || true
	for lab in "$labs"/0[1-4]-*; do
		make -s -C "$lab" unload 2>/dev/null || true
	done
}
trap cleanup EXIT

echo "building the labs"
make -s -C tools clean
make -s -C tools
cp "$try" "$trusted"
for lab in "$labs"/0*; do
	make -s -C "$lab" clean
	make -s -C "$lab"
done

echo "lab 01: hello"
make -s -C 01-hello-lsm load >/dev/null
clear_trace
expect_ok "$try" inet
traced "hello from the socket_bind LSM hook" || fail "lab 01 printed nothing"
make -s -C 01-hello-lsm unload

echo "lab 02: observe"
make -s -C 02-observe load >/dev/null
clear_trace
expect_ok "$try" inet
traced "bind(): comm=try-bind pid=[0-9]* family=2" || fail "lab 02 did not report the bind"
make -s -C 02-observe unload

echo "lab 03: deny by process name"
make -s -C 03-deny-comm load >/dev/null
expect_ok "$try" inet
expect_denied timeout 2 nc -l 127.0.0.1 45678
make -s -C 03-deny-comm unload
# Without the program, nc listens until timeout kills it (exit status 124).
rc=0
out=$(timeout 1 nc -l 127.0.0.1 45678 2>&1) || rc=$?
[ "$rc" -eq 124 ] || fail "nc could not listen after lab 03 was unloaded (status $rc): $out"

echo "lab 04: deny AF_ALG except for allowed names"
make -s -C 04-deny-af-alg load >/dev/null
expect_ok "$try" inet
expect_denied "$try" alg hash sha256
expect_denied "$try" alg aead "$aead"
expect_ok "$trusted" alg hash sha256
make -s -C 04-deny-af-alg unload
expect_ok "$try" alg aead "$aead"

echo "lab 05: copyfail_guard"
# Attaching to an LSM hook can take several seconds on a slow or busy host,
# because the kernel waits for all tasks before it changes the hook.
start_guard() {
	: >"$labs/guard.log"
	# The log belongs to this user on purpose, so the redirect stays outside sudo.
	# shellcheck disable=SC2024
	sudo "$labs/05-copyfail-guard/copyfail_guard" "$@" >"$labs/guard.log" 2>&1 &
	guard_pid=$!
	start=$(date +%s)
	until grep -q '^copyfail_guard attached' "$labs/guard.log"; do
		# The loader runs as root under sudo, so kill -0 from this user fails
		# with EPERM even while it runs. /proc shows the process to any user.
		running=yes
		[ -d "/proc/$guard_pid" ] || running=no
		if [ "$running" = no ] || [ $(($(date +%s) - start)) -ge 60 ]; then
			echo "copyfail_guard log:" >&2
			cat "$labs/guard.log" >&2
			loader=$(pgrep -x copyfail_guard || true)
			if [ -n "$loader" ]; then
				echo "kernel stack of the loader (pid $loader):" >&2
				sudo cat "/proc/$loader/stack" >&2 || true
			fi
			fail "copyfail_guard did not attach after $(($(date +%s) - start))s (still running: $running)"
		fi
		sleep 0.5
	done
	echo "  attached after $(($(date +%s) - start))s"
}
stop_guard() {
	sudo kill "$guard_pid"
	wait "$guard_pid" 2>/dev/null || true
	guard_pid=
}
logged() {
	tries=0
	until grep -q "$1" "$labs/guard.log"; do
		tries=$((tries + 1))
		[ "$tries" -lt 10 ] || { cat "$labs/guard.log" >&2; fail "copyfail_guard did not log: $1"; }
		sleep 0.5
	done
}

start_guard --allow "$trusted"
expect_ok "$try" inet
expect_ok "$try" alg hash sha256
expect_denied "$try" alg aead "$aead"
expect_denied "$try" alg aead 'gcm(aes)'
expect_ok "$trusted" alg aead "$aead"
# A different file with an allowed program's name must not get through.
mkdir -p "$labs/tools/fake"
cp "$try" "$labs/tools/fake/trusted-app"
expect_denied "$labs/tools/fake/trusted-app" alg aead "$aead"
logged "^DENIED: .*comm=try-bind algorithm=$aead"
logged "^DENIED: .*comm=trusted-app"
stop_guard
expect_ok "$try" alg aead "$aead"

echo LABS-TEST-PASS
