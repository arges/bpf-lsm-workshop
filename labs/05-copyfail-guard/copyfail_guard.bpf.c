// SPDX-License-Identifier: (GPL-2.0-only OR MIT)
/*
 * Lab 05: a complete mitigation for Copy Fail (CVE-2026-31431).
 *
 * The bug is in the kernel's AEAD socket interface (algif_aead). An exploit
 * has to bind() an AF_ALG socket with type "aead" before it can do anything
 * else, so denying that one bind() closes the door without a reboot and
 * without touching sockets of any other kind.
 *
 * Compared with lab 04 this program:
 *   - matches on the algorithm type inside the address, not just the family,
 *     so hashes and plain ciphers over AF_ALG keep working;
 *   - identifies allowed programs by executable file (device + inode), which
 *     a process cannot change, instead of by name, which it can;
 *   - takes its allow list from a map filled by the loader;
 *   - reports every denial to user space through a ring buffer.
 */
#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>
#include <bpf/bpf_core_read.h>
#include "copyfail_guard.h"

#define EPERM 1
#define AF_ALG 38

char LICENSE[] SEC("license") = "Dual MIT/GPL";

/* What bind(2) is given for an AF_ALG socket (struct sockaddr_alg). */
struct alg_addr {
	__u16 family;
	char type[SALG_TYPE_LEN];
	__u32 feat;
	__u32 mask;
	char name[SALG_NAME_LEN];
};

static const char aead_type[] = "aead";

/* Executables allowed to bind AF_ALG AEAD sockets. */
struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(max_entries, 64);
	__type(key, struct exe_id);
	__type(value, __u8);
} allowlist SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_RINGBUF);
	__uint(max_entries, 64 * 1024);
} events SEC(".maps");

static __always_inline bool current_exe_is_allowed(void)
{
	struct task_struct *task = bpf_get_current_task_btf();
	struct exe_id id = {};

	/*
	 * BPF_CORE_READ() walks the pointers safely: a kernel thread has no
	 * mm, in which case both fields read as 0 and nothing matches.
	 */
	id.ino = BPF_CORE_READ(task, mm, exe_file, f_inode, i_ino);
	id.dev = BPF_CORE_READ(task, mm, exe_file, f_inode, i_sb, s_dev);

	return bpf_map_lookup_elem(&allowlist, &id) != NULL;
}

SEC("lsm/socket_bind")
int BPF_PROG(copyfail_guard, struct socket *sock, struct sockaddr *address, int addrlen, int ret)
{
	struct alg_addr alg = {};
	struct event *e;

	if (ret)
		return ret;

	if (address->sa_family != AF_ALG)
		return 0;

	/* Too short to be a valid AF_ALG address; the kernel rejects it. */
	if (addrlen < sizeof(alg))
		return 0;

	if (bpf_probe_read_kernel(&alg, sizeof(alg), address) < 0)
		return 0;

	/* Only the AEAD interface is affected. */
	if (bpf_strncmp(alg.type, sizeof(alg.type), aead_type) != 0)
		return 0;

	if (current_exe_is_allowed())
		return 0;

	/* Report the denial to the loader. */
	e = bpf_ringbuf_reserve(&events, sizeof(*e), 0);
	if (e) {
		e->pid = bpf_get_current_pid_tgid() >> 32;
		e->uid = bpf_get_current_uid_gid();
		bpf_get_current_comm(e->comm, sizeof(e->comm));
		__builtin_memcpy(e->salg_name, alg.name, sizeof(e->salg_name));
		e->salg_name[sizeof(e->salg_name) - 1] = '\0';
		bpf_ringbuf_submit(e, 0);
	}

	return -EPERM;
}
