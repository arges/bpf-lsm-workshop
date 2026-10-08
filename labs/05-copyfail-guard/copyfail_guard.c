// SPDX-License-Identifier: (GPL-2.0-only OR MIT)
/*
 * Loader for copyfail_guard.bpf.c.
 *
 *   sudo ./copyfail_guard [--allow /path/to/program]...
 *
 * Loads and attaches the BPF LSM program, then prints one line for every
 * denied AF_ALG AEAD bind() until interrupted. The mitigation is removed
 * when this program exits.
 */
#include <errno.h>
#include <getopt.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>

#include <bpf/libbpf.h>

#include "copyfail_guard.h"
#include "copyfail_guard.skel.h"

static volatile sig_atomic_t stop;

static void on_signal(int sig)
{
	stop = 1;
}

/*
 * The kernel's dev_t packs major and minor numbers differently from the
 * st_dev that stat(2) returns: (major << 20) | minor.
 */
static __u64 kernel_dev(dev_t dev)
{
	return ((__u64)major(dev) << 20) | minor(dev);
}

static int allow_path(struct copyfail_guard_bpf *skel, const char *path)
{
	struct exe_id id;
	struct stat st;
	__u8 one = 1;

	if (stat(path, &st) < 0) {
		fprintf(stderr, "cannot allow %s: %s\n", path, strerror(errno));
		return -1;
	}
	id.dev = kernel_dev(st.st_dev);
	id.ino = st.st_ino;

	if (bpf_map__update_elem(skel->maps.allowlist, &id, sizeof(id), &one, sizeof(one), BPF_ANY)) {
		fprintf(stderr, "cannot allow %s: map update failed\n", path);
		return -1;
	}
	printf("allowing %s\n", path);
	return 0;
}

static int on_event(void *ctx, void *data, size_t size)
{
	const struct event *e = data;

	printf("DENIED: pid=%u uid=%u comm=%s algorithm=%s\n",
	       e->pid, e->uid, e->comm, e->salg_name);
	fflush(stdout);
	return 0;
}

int main(int argc, char **argv)
{
	static const struct option options[] = {
		{ "allow", required_argument, NULL, 'p' },
		{ "help", no_argument, NULL, 'h' },
		{}
	};
	struct copyfail_guard_bpf *skel;
	struct ring_buffer *rb = NULL;
	int opt, err = 1;

	/* One line at a time, also when the output goes to a file. */
	setvbuf(stdout, NULL, _IOLBF, 0);

	skel = copyfail_guard_bpf__open();
	if (!skel) {
		fprintf(stderr, "failed to open the BPF program\n");
		return 1;
	}

	if (copyfail_guard_bpf__load(skel)) {
		fprintf(stderr, "failed to load the BPF program (are you root?)\n");
		goto out;
	}

	/* Fill the allow list, which exists only after loading. */
	while ((opt = getopt_long(argc, argv, "p:h", options, NULL)) != -1) {
		if (opt != 'p') {
			fprintf(stderr, "usage: %s [--allow PATH]...\n", argv[0]);
			goto out;
		}
		if (allow_path(skel, optarg))
			goto out;
	}

	if (copyfail_guard_bpf__attach(skel)) {
		fprintf(stderr, "failed to attach the BPF program\n");
		goto out;
	}

	rb = ring_buffer__new(bpf_map__fd(skel->maps.events), on_event, NULL, NULL);
	if (!rb) {
		fprintf(stderr, "failed to open the ring buffer\n");
		goto out;
	}

	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);

	printf("copyfail_guard attached; Ctrl-C to remove\n");
	fflush(stdout);

	while (!stop) {
		int n = ring_buffer__poll(rb, 200);

		if (n < 0 && n != -EINTR) {
			fprintf(stderr, "ring buffer error: %d\n", n);
			goto out;
		}
	}
	err = 0;
out:
	ring_buffer__free(rb);
	copyfail_guard_bpf__destroy(skel);
	return err;
}
