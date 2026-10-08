// SPDX-License-Identifier: (GPL-2.0-only OR MIT)
/*
 * Loader for deny_mkdir.bpf.c: loads and attaches the BPF LSM program, prints
 * "attached", and keeps it attached until it receives SIGINT or SIGTERM.
 */
#include <signal.h>
#include <stdio.h>
#include <unistd.h>

#include "deny_mkdir.skel.h"

static volatile sig_atomic_t stop;

static void on_signal(int sig)
{
	stop = 1;
}

int main(void)
{
	struct deny_mkdir_bpf *skel;
	int err;

	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);

	skel = deny_mkdir_bpf__open_and_load();
	if (!skel) {
		fprintf(stderr, "failed to open and load the BPF program\n");
		return 1;
	}

	err = deny_mkdir_bpf__attach(skel);
	if (err) {
		fprintf(stderr, "failed to attach: %d\n", err);
		deny_mkdir_bpf__destroy(skel);
		return 1;
	}

	puts("attached");
	fflush(stdout);

	while (!stop)
		pause();

	deny_mkdir_bpf__destroy(skel);
	return 0;
}
