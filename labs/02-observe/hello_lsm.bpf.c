// SPDX-License-Identifier: (GPL-2.0-only OR MIT)
/*
 * Lab 02: observe before you enforce.
 *
 * Same hook as lab 01, but now the program reports who called bind(2) and
 * with what: the process name (comm), its PID, and the address family of the
 * address being bound. Nothing is blocked.
 */
#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

char LICENSE[] SEC("license") = "Dual MIT/GPL";

SEC("lsm/socket_bind")
int BPF_PROG(hello_lsm, struct socket *sock, struct sockaddr *address, int addrlen, int ret)
{
	char comm[TASK_COMM_LEN];
	__u32 pid = bpf_get_current_pid_tgid() >> 32;

	/* The hook runs in the context of the process making the system call. */
	bpf_get_current_comm(comm, sizeof(comm));

	/*
	 * address points at the kernel's copy of the sockaddr passed to
	 * bind(2). The verifier knows its type from BTF, so fields can be
	 * read directly.
	 */
	bpf_printk("bind(): comm=%s pid=%d family=%d", comm, pid, address->sa_family);

	return ret;
}
