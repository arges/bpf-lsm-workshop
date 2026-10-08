// SPDX-License-Identifier: (GPL-2.0-only OR MIT)
/*
 * Lab 03: the first denial.
 *
 * Deny bind(2) to any process whose name is "nc". Every other process is
 * unaffected.
 */
#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

#define EPERM 1

char LICENSE[] SEC("license") = "Dual MIT/GPL";

/* The process name to deny. Must be shorter than TASK_COMM_LEN (16). */
static const char denied_comm[] = "nc";

SEC("lsm/socket_bind")
int BPF_PROG(hello_lsm, struct socket *sock, struct sockaddr *address, int addrlen, int ret)
{
	char comm[TASK_COMM_LEN];

	/* An earlier LSM already denied this; do not override it. */
	if (ret)
		return ret;

	bpf_get_current_comm(comm, sizeof(comm));
	if (bpf_strncmp(comm, sizeof(comm), denied_comm) != 0)
		return 0;

	__u32 pid = bpf_get_current_pid_tgid() >> 32;

	bpf_printk("denied bind(): comm=%s pid=%d family=%d",
		   comm, pid, address->sa_family);
	return -EPERM;
}
