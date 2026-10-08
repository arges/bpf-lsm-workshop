# BPF-LSM workshop VM image.
#
# Run `make` for a list of targets. Everything large ends up in cache/, build/
# and dist/, which are not tracked by git.

.DEFAULT_GOAL := help

include versions.mk

HOST_ARCH := $(shell uname -m | sed -e 's/^x86_64$$/amd64/' -e 's/^aarch64$$/arm64/')

ARCH      ?= $(HOST_ARCH)
DISK_SIZE ?= 8G
MEM       ?= 2048
CPUS      ?= 2
SSH_PORT  ?= 2222
FORMAT    ?=

ifeq ($(filter $(ARCH),amd64 arm64),)
$(error ARCH must be amd64 or arm64 (got '$(ARCH)'))
endif

export DISK_SIZE MEM CPUS SSH_PORT

NAME      := bpf-lsm-workshop
BASE_NAME := debian-$(DEBIAN_VERSION)-generic-$(ARCH)-$(BASE_SERIAL).qcow2
BASE_URL  := https://cloud.debian.org/images/cloud/$(DEBIAN_RELEASE)/$(BASE_SERIAL)/$(BASE_NAME)
BASE      := cache/$(BASE_NAME)
IMAGE     := build/$(NAME)-$(ARCH).qcow2
RUN_DISK  := build/run-$(ARCH).qcow2
RUN_PID   := build/run-$(ARCH).pid
RUN_LOG   := build/run-$(ARCH).log
OVA       := build/$(NAME)-amd64.ova
UTM       := build/$(NAME)-arm64.utm.zip
CONVERTED := build/$(NAME)-$(ARCH).$(FORMAT)
LAB_SOURCES := $(wildcard labs/*.md labs/*.mk labs/*.sh labs/*/Makefile \
	labs/*/README.md labs/*/*.c) labs/05-copyfail-guard/copyfail_guard.h

# GitHub rejects release assets of 2 GiB or more.
MAX_ASSET_BYTES := 2147483647

.PHONY: help
help: ## Show this help
	@echo "Targets:"
	@awk -F ':.*## ' '/^[a-z-]+:.*## /{printf "  %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Variables (current value):"
	@echo "  ARCH=$(ARCH)  DISK_SIZE=$(DISK_SIZE)  MEM=$(MEM)  CPUS=$(CPUS)  SSH_PORT=$(SSH_PORT)"
	@echo "  BUILD_TIMEOUT, AAVMF_CODE, FORMAT: see specs/001-workshop-vm-image/contracts/make-targets.md"

.PHONY: fetch
fetch: $(BASE) ## Download and verify the pinned Debian base image

$(BASE):
	scripts/fetch.sh '$(BASE_URL)' '$(BASE_SHA512_$(ARCH))' $@

.PHONY: image
image: $(IMAGE) ## Build the workshop VM image (build/bpf-lsm-workshop-ARCH.qcow2)

$(IMAGE): $(BASE) versions.mk scripts/build-image.sh scripts/provision.sh scripts/lib.sh $(LAB_SOURCES)
	scripts/build-image.sh $(ARCH) $(BASE) $@

.PHONY: test
test: $(IMAGE) ## Boot the image; build and exercise the smoke test and every lab inside it
	tests/smoke-test.sh $(ARCH) $(IMAGE)

# `run` works on a copy-on-write overlay so the image you publish is never
# modified. Rebuilding the image discards the overlay.
$(RUN_DISK): $(IMAGE)
	rm -f $@
	qemu-img create -q -f qcow2 -F qcow2 -b $(abspath $(IMAGE)) $@

.PHONY: run
run: $(RUN_DISK) ## Boot the image interactively (serial console; quit with Ctrl-a x)
	scripts/run-vm.sh $(ARCH) $(RUN_DISK)

.PHONY: start
start: $(RUN_DISK) ## Start the VM in the background and wait for SSH
	scripts/headless-vm.sh start $(ARCH) $(RUN_DISK) $(RUN_PID) $(RUN_LOG)

.PHONY: stop
stop: ## Shut down a VM started with `make start`
	scripts/headless-vm.sh stop $(ARCH) $(RUN_DISK) $(RUN_PID) $(RUN_LOG)

.PHONY: ssh
ssh: ## Open SSH to a VM started with `make start` or `make run`
	scripts/ssh-vm.sh

.PHONY: ova
ova: $(OVA) ## Package the amd64 image as an OVA for VirtualBox / VMware

$(OVA): build/$(NAME)-amd64.qcow2 scripts/make-ova.sh
ifneq ($(ARCH),amd64)
	$(error the OVA is only built for amd64; run `make ova ARCH=amd64`)
endif
	scripts/make-ova.sh $< $@

.PHONY: utm
utm: $(UTM) ## Package the arm64 image as a UTM VM for Apple silicon Macs

$(UTM): build/$(NAME)-arm64.qcow2 scripts/make-utm.sh
ifneq ($(ARCH),arm64)
	$(error the UTM bundle is only built for arm64; run `make utm ARCH=arm64`)
endif
	scripts/make-utm.sh $< $@

.PHONY: convert
convert: ## Convert the image with qemu-img: FORMAT=vhdx|vdi|vmdk|raw
ifeq ($(filter $(FORMAT),vhdx vdi vmdk raw),)
	$(error set FORMAT to one of: vhdx vdi vmdk raw)
endif
	@$(MAKE) --no-print-directory $(CONVERTED)

ifneq ($(FORMAT),)
$(CONVERTED): $(IMAGE)
	qemu-img convert -O $(FORMAT) $< $@.tmp
	mv $@.tmp $@
endif

.PHONY: dist
dist: ## Collect built images and SHA256SUMS in dist/ for a GitHub release
	@rm -rf dist && mkdir -p dist
	@found=0; \
	for f in build/$(NAME)-*.qcow2 build/$(NAME)-*.ova build/$(NAME)-*.utm.zip build/$(NAME)-*.packages.txt; do \
		[ -f "$$f" ] || continue; \
		ln -f "$$f" dist/ 2>/dev/null || cp "$$f" dist/; \
		found=1; \
	done; \
	[ "$$found" = 1 ] || { echo "error: nothing to package; run 'make image' first" >&2; exit 1; }
	@big=$$(find dist -type f -size +$(MAX_ASSET_BYTES)c); \
	[ -z "$$big" ] || { echo "error: too large for a GitHub release asset (2 GiB limit):" >&2; echo "$$big" >&2; exit 1; }
	cd dist && sha256sum $(NAME)-* > SHA256SUMS
	@ls -lh dist

.PHONY: slides
slides: ## Render the workshop slides to slides/slides.html
	npx --yes @marp-team/marp-cli@latest \
		--theme-set slides/themes/cloudflare-light.css \
		--html --allow-local-files \
		slides/slides.md -o slides/slides.html

# User-facing docs are written in plain English (Simplified Technical English).
STE_LINT := .claude/skills/asd-ste100/scripts/ste-lint.py
DOCS := README.md docs/*.md labs/README.md labs/*/README.md

.PHONY: check
check: ## Lint the shell scripts (shellcheck) and the docs (STE linter)
	python3 $(STE_LINT) $(DOCS)
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -x scripts/*.sh tests/*.sh tests/guest/*.sh labs/*.sh && echo "shellcheck: ok"; \
	else \
		echo "shellcheck not installed; checking syntax only"; \
		for f in scripts/*.sh tests/*.sh tests/guest/*.sh labs/*.sh; do sh -n "$$f" || exit 1; done; \
	fi

.PHONY: clean
clean: ## Remove build/ and dist/
	rm -rf build dist

.PHONY: distclean
distclean: clean ## Also remove downloaded base images
	rm -rf cache
