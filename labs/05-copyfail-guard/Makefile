NAME := copyfail_guard
EXTRA_BPF_DEPS := copyfail_guard.h
EXTRA_CLEAN := copyfail_guard
include ../common.mk

# This lab has its own loader instead of using bpftool: it fills the allow
# list and prints denials.
all: copyfail_guard

copyfail_guard.skel.h: copyfail_guard.bpf.o
	bpftool gen skeleton $< > $@

copyfail_guard: copyfail_guard.c copyfail_guard.skel.h copyfail_guard.h
	gcc -O2 -g -Wall -Werror $< -o $@ $$(pkg-config --libs libbpf)
