// SPDX-License-Identifier: (GPL-2.0-only OR MIT)
/*
 * Lab 01: the smallest useful BPF LSM program.
 *
 * It attaches to the socket_bind LSM hook, which the kernel calls whenever a
 * process calls bind(2), says hello in the trace log, and allows the call.
 */
#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

/* bpf_printk() is a GPL-only helper, so the program must be GPL compatible. */
char LICENSE[] SEC("license") = "Dual MIT/GPL";

/*
 * SEC("lsm/<hook>") picks the hook. The arguments are the hook's arguments,
 * as declared in include/linux/lsm_hook_defs.h in the kernel source:
 *
 *   LSM_HOOK(int, 0, socket_bind, struct socket *sock,
 *            struct sockaddr *address, int addrlen)
 *
 * followed by one extra argument: the verdict of the LSM programs that ran
 * before this one.
 */
SEC("lsm/socket_bind")
int BPF_PROG(hello_lsm, struct socket *sock, struct sockaddr *address, int addrlen, int ret)
{
	bpf_printk("hello from the socket_bind LSM hook");

	/* 0 allows the operation; a negative errno such as -EPERM denies it. */
	return ret;
}
