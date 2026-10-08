# Shared build rules for the labs. Each lab's Makefile sets NAME and includes
# this file. Run these inside the workshop VM.
#
#   make          build $(NAME).bpf.o
#   make load     load the program and attach it to its LSM hook
#   make unload   detach and unload it
#   make trace    follow bpf_printk() output (Ctrl-C to stop)

LABS := $(dir $(lastword $(MAKEFILE_LIST)))
VMLINUX := $(LABS)vmlinux.h
BPF_ARCH := $(shell uname -m | sed -e 's/x86_64/x86/' -e 's/aarch64/arm64/')
# Since Linux 6.19 the kernel embeds unnamed structs by tag, and vmlinux.h
# repeats them. clang accepts that only with -fms-extensions.
BPF_CFLAGS := -O2 -g -Wall -Werror -fms-extensions -Wno-microsoft-anon-tag \
	-target bpf -D__TARGET_ARCH_$(BPF_ARCH) -I$(LABS)

# With autoattach, bpftool pins the attachment here; removing the pin
# detaches the program.
PIN := /sys/fs/bpf/$(NAME)

.DEFAULT_GOAL := all
.DELETE_ON_ERROR:

.PHONY: all
all: $(NAME).bpf.o

# Every kernel type, generated from the running kernel's BTF. This replaces
# kernel headers.
$(VMLINUX):
	bpftool btf dump file /sys/kernel/btf/vmlinux format c > $@

$(NAME).bpf.o: $(NAME).bpf.c $(VMLINUX) $(EXTRA_BPF_DEPS)
	clang $(BPF_CFLAGS) -c $< -o $@

.PHONY: load
load: $(NAME).bpf.o unload
	sudo bpftool prog load $(NAME).bpf.o $(PIN) autoattach
	@echo "loaded; run 'make trace' in another terminal, 'make unload' to remove"

# Removing the pin releases the link. The kernel then detaches the program a
# moment later, from a work queue. Wait until the program is gone, so that the
# next command does not still see it.
.PHONY: unload
unload:
	sudo rm -f $(PIN)
	@tries=0; \
	while [ -n "$$(sudo bpftool prog show name $(NAME) 2>/dev/null)" ]; do \
		tries=$$((tries + 1)); \
		if [ $$tries -ge 100 ]; then \
			echo "error: $(NAME) is still loaded after 10 seconds" >&2; exit 1; \
		fi; \
		sleep 0.1; \
	done

.PHONY: trace
trace:
	sudo bpftool prog tracelog

.PHONY: clean
clean:
	rm -f *.bpf.o *.skel.h $(EXTRA_CLEAN)
