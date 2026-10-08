// SPDX-License-Identifier: (GPL-2.0-only OR MIT)
/*
 * Lab 04: deny by argument, with an allow list.
 *
 * Deny bind(2) only when the address being bound is an AF_ALG address (the
 * kernel crypto API socket family that Copy Fail abuses), and only for
 * processes whose name is not on a short allow list.
 */
#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

#define EPERM 1
#define AF_ALG 38

char LICENSE[] SEC("license") = "Dual MIT/GPL";

/* Process names that may keep using AF_ALG. */
static const char allowed_1[] = "trusted-app";
static const char allowed_2[] = "cryptsetup";

static __always_inline bool comm_is_allowed(const char *comm)
{
	return bpf_strncmp(comm, TASK_COMM_LEN, allowed_1) == 0 ||
	       bpf_strncmp(comm, TASK_COMM_LEN, allowed_2) == 0;
}

SEC("lsm/socket_bind")
int BPF_PROG(hello_lsm, struct socket *sock, struct sockaddr *address, int addrlen, int ret)
{
	char comm[TASK_COMM_LEN];

	if (ret)
		return ret;

	/* The argument check: everything except AF_ALG passes untouched. */
	if (address->sa_family != AF_ALG)
		return 0;

	bpf_get_current_comm(comm, sizeof(comm));
	if (comm_is_allowed(comm))
		return 0;

	__u32 pid = bpf_get_current_pid_tgid() >> 32;

	bpf_printk("denied bind(): comm=%s pid=%d family=%d",
		   comm, pid, address->sa_family);
	return -EPERM;
}
