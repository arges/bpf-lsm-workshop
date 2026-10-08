/* SPDX-License-Identifier: (GPL-2.0-only OR MIT) */
/* Definitions shared by the BPF program and its loader. */
#ifndef COPYFAIL_GUARD_H
#define COPYFAIL_GUARD_H

#define COMM_LEN 16
#define SALG_TYPE_LEN 14
#define SALG_NAME_LEN 64

/* Identifies an executable file: the device it is on and its inode number. */
struct exe_id {
	__u64 dev;
	__u64 ino;
};

/* One denied AF_ALG AEAD bind(), sent to user space. */
struct event {
	__u32 pid;
	__u32 uid;
	char comm[COMM_LEN];
	char salg_name[SALG_NAME_LEN];
};

#endif
