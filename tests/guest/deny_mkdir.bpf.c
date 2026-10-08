// SPDX-License-Identifier: (GPL-2.0-only OR MIT)
/*
 * Smoke-test BPF LSM program: deny creating any directory named
 * "bpf-lsm-denied". Everything else is left alone.
 *
 * This is not workshop material; it only proves that the VM image can
 * compile, load and enforce a BPF LSM program.
 */
#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

#define EPERM 1

/* GPL-only helpers are used, so the kernel needs a GPL-compatible string. */
char LICENSE[] SEC("license") = "Dual MIT/GPL";

static const char denied[] = "bpf-lsm-denied";

SEC("lsm/inode_mkdir")
int BPF_PROG(deny_mkdir, struct inode *dir, struct dentry *dentry, umode_t mode, int ret)
{
	char name[sizeof(denied)] = {};

	/* Respect a denial from an earlier LSM in the chain. */
	if (ret)
		return ret;

	if (bpf_probe_read_kernel_str(name, sizeof(name), dentry->d_name.name) < 0)
		return 0;

	if (bpf_strncmp(name, sizeof(name), denied) != 0)
		return 0;

	return -EPERM;
}
