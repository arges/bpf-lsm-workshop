# Builds the smoke-test BPF LSM program inside the workshop VM:
# BPF object with clang, libbpf skeleton with bpftool, loader with gcc.

CC := gcc
BPF_ARCH := $(shell uname -m | sed -e 's/x86_64/x86/' -e 's/aarch64/arm64/')

.DELETE_ON_ERROR:

deny_mkdir: deny_mkdir.c deny_mkdir.skel.h
	$(CC) -O2 -g -Wall -Werror $< -o $@ $$(pkg-config --libs libbpf)

deny_mkdir.skel.h: deny_mkdir.bpf.o
	bpftool gen skeleton $< > $@

deny_mkdir.bpf.o: deny_mkdir.bpf.c vmlinux.h
	clang -O2 -g -Wall -Werror -fms-extensions -Wno-microsoft-anon-tag \
		-target bpf -D__TARGET_ARCH_$(BPF_ARCH) -c $< -o $@

vmlinux.h:
	bpftool btf dump file /sys/kernel/btf/vmlinux format c > $@

.PHONY: clean
clean:
	rm -f deny_mkdir deny_mkdir.skel.h deny_mkdir.bpf.o vmlinux.h
