#!/bin/sh
# Guest-side provisioning for the BPF-LSM workshop VM.
#
# This file is served verbatim as cloud-init user-data and runs once, as root,
# on the first boot of the Debian cloud image (see scripts/build-image.sh).
#
# It runs in two stages. Stage 1 runs under cloud-init and sets the system up.
# Stage 2 ("finalize") removes cloud-init itself, which cannot be done from a
# process cloud-init started, so stage 1 hands it to a transient systemd unit.
# Stage 2 reports the result on the serial console and powers the VM off; the
# build host only keeps the image if it sees WORKSHOP-PROVISION-OK.
set -eu

exec >/dev/console 2>&1

WORKSHOP_USER=workshop
WORKSHOP_PASSWORD=workshop
WORKSHOP_HOSTNAME=bpf-lsm-workshop
FINALIZE=/run/workshop-finalize.sh
WORKSHOP_DIR=/home/$WORKSHOP_USER/bpf-lsm-workshop
LABS_URL=@LABS_URL@
LABS_SHA256=@LABS_SHA256@
# Debian's bpftool omits both JIT disassembly backends. Build the matching
# upstream release with libbfd and pin its signed tag's commit.
BPFTOOL_VERSION=7.5.0
BPFTOOL_COMMIT=d844a27fc175aeae3bcb29b052813ef210c97004

export DEBIAN_FRONTEND=noninteractive

step() { echo "[provision] $*"; }

apt_get() { apt-get -y -o DPkg::Lock::Timeout=300 "$@"; }

on_exit() {
	rc=$?
	trap - EXIT
	if [ "$rc" -ne 0 ]; then
		echo WORKSHOP-PROVISION-FAILED
		sync
		poweroff
	fi
}
trap on_exit EXIT

# Tell dpkg not to unpack files nobody will use in a workshop. This applies to
# everything installed from here on; slim_installed_files handles what the
# base image already contains.
configure_dpkg_excludes() {
	cat >/etc/dpkg/dpkg.cfg.d/workshop-slim <<'CFG'
# Translations, and documentation other than licences and English man pages.
path-exclude=/usr/share/locale/*
path-include=/usr/share/locale/locale.alias
path-exclude=/usr/share/doc/*
path-include=/usr/share/doc/*/copyright
path-exclude=/usr/share/man/*
path-include=/usr/share/man/man[1-9]/*
path-exclude=/usr/share/info/*

# LLVM developer tools that dwarf the ones a BPF workflow uses
# (llvm-objdump, llvm-strip, llvm-readelf and friends are kept).
path-exclude=/usr/lib/llvm-*/bin/llvm-exegesis
path-exclude=/usr/lib/llvm-*/bin/obj2yaml
path-exclude=/usr/lib/llvm-*/bin/yaml2obj
path-exclude=/usr/lib/llvm-*/bin/llvm-tblgen
path-exclude=/usr/lib/llvm-*/bin/llvm-pdbutil
path-exclude=/usr/lib/llvm-*/bin/llvm-jitlink-executor
path-exclude=/usr/lib/llvm-*/bin/lli-child-target

# GCC's LTO dump utility (a compiler-debugging aid; -flto itself still works)
# and the C++ standard library headers, which clang pulls in as a dependency
# although the image has no C++ compiler.
path-exclude=/usr/bin/*lto-dump*
path-exclude=/usr/include/c++/*
path-exclude=/usr/lib/gcc/*/*/libstdc++*.a
path-exclude=/usr/lib/gcc/*/*/libsupc++.a

# Vim extras: message translations, spell files and the tutor. Syntax
# highlighting and :help are kept.
path-exclude=/usr/share/vim/vim*/lang/*
path-exclude=/usr/share/vim/vim*/spell/*
path-exclude=/usr/share/vim/vim*/tutor/*
CFG
}

backports_suite() {
	echo "$(. /etc/os-release && echo "$VERSION_CODENAME")-backports"
}

# Some cloud images already list backports. Add it only when they do not, so
# apt does not warn about a duplicate source.
enable_backports() {
	suite=$(backports_suite)
	if grep -rqsw -- "$suite" /etc/apt/sources.list /etc/apt/sources.list.d/; then
		return
	fi
	cat >/etc/apt/sources.list.d/backports.sources <<-EOF
		Types: deb
		URIs: http://deb.debian.org/debian
		Suites: $suite
		Components: main
		Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
	EOF
}

# Remove every kernel except the newest. The build runs on the old kernel, and
# its prerm script asks before it removes the running kernel. The default
# answer aborts, so answer it first.
purge_old_kernels() {
	newest=$(dpkg-query -W -f='${Package}\n' 'linux-image-[0-9]*' | sort -V | tail -n 1)
	running=$(uname -r)
	echo "linux-image-$running linux-image-$running/prerm/removing-running-kernel-$running boolean false" |
		debconf-set-selections
	old=$(dpkg-query -W -f='${Package}\n' 'linux-image-[0-9]*' | grep -vx "$newest" || true)
	if [ -n "$old" ]; then
		# shellcheck disable=SC2086  # one package name per word
		apt_get purge $old
	fi
	step "kernel: $newest"
}

slim_installed_files() {
	find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name locale.alias -exec rm -rf {} +
	find /usr/share/doc -mindepth 2 ! -name copyright ! -type d -delete
	find /usr/share/doc -mindepth 1 -type d -empty -delete
	find /usr/share/man -mindepth 1 -maxdepth 1 ! -name 'man[1-9]' -exec rm -rf {} +
	rm -rf /usr/share/info/*
}

# Remove kernel modules for hardware no virtual machine presents. Everything a
# hypervisor might emulate is kept: all storage controllers, virtio, Hyper-V,
# VMware and Xen drivers, USB, input, and the common emulated network cards.
prune_kernel_modules() {
	for kdir in /usr/lib/modules/*/kernel; do
		[ -d "$kdir" ] || continue
		kver=$(basename "$(dirname "$kdir")")
		before=$(du -sm "$kdir" | cut -f1)
		(
			cd "$kdir"
			rm -rf sound \
				net/wireless net/mac80211 net/bluetooth net/nfc net/can \
				net/ieee802154 net/mac802154 net/6lowpan \
				drivers/net/wireless drivers/net/can drivers/net/wwan \
				drivers/net/ieee802154 drivers/net/hamradio drivers/net/arcnet \
				drivers/net/fddi drivers/net/wan \
				drivers/bluetooth drivers/nfc drivers/media drivers/infiniband \
				drivers/iio drivers/staging drivers/isdn drivers/comedi \
				drivers/mtd drivers/thunderbolt drivers/accel \
				drivers/platform drivers/hwmon drivers/edac drivers/atm \
				drivers/mmc drivers/memstick drivers/target drivers/leds \
				drivers/power drivers/regulator drivers/mfd drivers/pcmcia \
				drivers/parport drivers/firewire drivers/ssb drivers/bcma \
				drivers/net/ethernet/intel/ice drivers/net/ethernet/intel/i40e \
				drivers/net/ethernet/intel/ixgbe drivers/net/ethernet/intel/idpf \
				drivers/net/ethernet/intel/igc drivers/net/ethernet/intel/iavf \
				drivers/net/ethernet/intel/ixgbevf drivers/net/ethernet/intel/fm10k \
				net/sctp net/ceph net/atm net/rxrpc net/tipc net/rds net/batman-adv \
				net/appletalk net/ax25 net/netrom net/rose net/dccp net/l2tp \
				fs/bcachefs fs/btrfs fs/xfs fs/ocfs2 fs/f2fs fs/gfs2 fs/ceph \
				fs/jfs fs/reiserfs fs/nilfs2 fs/ubifs fs/jffs2 fs/afs fs/orangefs \
				fs/coda fs/hfs fs/hfsplus fs/ufs fs/minix fs/erofs fs/ntfs3 \
				fs/exfat fs/udf fs/dlm fs/ocfs2 fs/nfsd fs/smb \
				drivers/gpu/drm/amd drivers/gpu/drm/i915 drivers/gpu/drm/xe \
				drivers/gpu/drm/nouveau drivers/gpu/drm/radeon
			# Fibre Channel, SAS and hardware RAID adapters live in
			# subdirectories of drivers/scsi; the paravirtual and emulated
			# controllers (virtio, pvscsi, storvsc, BusLogic, LSI, megaraid)
			# are kept.
			if [ -d drivers/scsi ]; then
				find drivers/scsi -mindepth 1 -maxdepth 1 -type d \
					! -name megaraid ! -name sym53c8xx_2 ! -name device_handler \
					-exec rm -rf {} +
			fi
			# Physical NICs: keep only the vendors hypervisors emulate
			# (e1000/e1000e, pcnet32, rtl8139) plus Azure's.
			if [ -d drivers/net/ethernet ]; then
				find drivers/net/ethernet -mindepth 1 -maxdepth 1 \
					! -name intel ! -name amd ! -name realtek ! -name microsoft \
					-exec rm -rf {} +
			fi
		)
		depmod -a "$kver"
		step "kernel modules for $kver: ${before} MB -> $(du -sm "$kdir" | cut -f1) MB"
	done
}
build_bpftool() {
	src=/tmp/bpftool
	tag=v$BPFTOOL_VERSION

	step "building bpftool $BPFTOOL_VERSION with JIT disassembly support"
	git clone --quiet --depth 1 --branch "$tag" --recurse-submodules --shallow-submodules \
		https://github.com/libbpf/bpftool.git "$src"
	actual=$(git -C "$src" rev-parse HEAD)
	if [ "$actual" != "$BPFTOOL_COMMIT" ]; then
		echo "bpftool $tag resolved to unexpected commit $actual"
		exit 1
	fi
	make -C "$src/src" -j"$(nproc)"
	if ! "$src/src/bpftool" version | grep -Eq 'features:.*(libbfd|llvm)'; then
		echo "the workshop bpftool was built without JIT disassembly support"
		exit 1
	fi
	install -m 0755 "$src/src/bpftool" /usr/local/bin/bpftool
	rm -rf "$src"

	# Headers and unversioned linker names are build-only. The installed binary
	# uses the versioned libbfd and libopcodes libraries from libbinutils.
	apt_get purge binutils-dev
	bpftool version | grep -Eq 'features:.*(libbfd|llvm)' || {
		echo "the installed bpftool lost its JIT disassembly backend"
		exit 1
	}
}

install_labs() {
	archive=/tmp/workshop-labs.tar.gz
	step "installing workshop labs"
	curl --fail --silent --show-error "$LABS_URL" -o "$archive"
	echo "$LABS_SHA256  $archive" | sha256sum -c -
	mkdir -p "$WORKSHOP_DIR"
	tar -xzf "$archive" -C "$WORKSHOP_DIR"
	chown -R "$WORKSHOP_USER:$WORKSHOP_USER" "$WORKSHOP_DIR"
	rm -f "$archive"
}

stage1() {
	step "checking that the BPF LSM is active"
	if ! tr ',' '\n' </sys/kernel/security/lsm | grep -qx bpf; then
		echo "bpf is not in /sys/kernel/security/lsm: $(cat /sys/kernel/security/lsm)"
		exit 1
	fi

	step "installing packages"
	configure_dpkg_excludes
	enable_backports
	apt_get update
	# The stable kernel is too old for the labs, so take the kernel from
	# backports. Stage 2 removes the stable kernel.
	apt_get install -t "$(backports_suite)" "linux-image-$(dpkg --print-architecture)"
	# No kernel headers: BPF LSM programs are built CO-RE style against a
	# vmlinux.h generated from /sys/kernel/btf/vmlinux. No C++ compiler.
	# The last line names tools the base image already has, so that they
	# survive the autoremove in stage 2.
	apt_get install --no-install-recommends \
		clang llvm libbpf-dev bpftool libelf-dev zlib1g-dev pkgconf \
		gcc libc6-dev make binutils-dev \
		git vim nano less curl ca-certificates strace bpftrace tmux \
		bash-completion man-db manpages-dev \
		iproute2 file libcap2-bin netcat-openbsd
	build_bpftool

	step "smoothing over Debian packaging quirks"
	# clang -target bpf does not search the multiarch include directory, so
	# <linux/types.h> fails with "asm/types.h not found" without this.
	[ -e /usr/include/asm ] || ln -s "/usr/include/$(gcc -print-multiarch)/asm" /usr/include/asm

	step "creating the $WORKSHOP_USER user"
	# Drop the cloud image's default account first so ours gets uid 1000.
	if id debian >/dev/null 2>&1; then
		userdel --remove debian
	fi
	rm -f /etc/sudoers.d/90-cloud-init-users
	useradd --create-home --shell /bin/bash --groups sudo "$WORKSHOP_USER"
	echo "$WORKSHOP_USER:$WORKSHOP_PASSWORD" | chpasswd
	echo "$WORKSHOP_USER ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/workshop
	chmod 0440 /etc/sudoers.d/workshop
	install_labs

	step "configuring ssh"
	echo "PasswordAuthentication yes" >/etc/ssh/sshd_config.d/10-workshop.conf
	# Host keys must be unique per VM, so they are not shipped in the image.
	cat >/etc/systemd/system/workshop-ssh-hostkeys.service <<'UNIT'
[Unit]
Description=Generate SSH host keys on first boot
Before=ssh.service
ConditionPathExists=!/etc/ssh/ssh_host_ed25519_key

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A

[Install]
WantedBy=multi-user.target
UNIT
	systemctl enable workshop-ssh-hostkeys.service

	step "making networking independent of the build VM"
	# cloud-init pinned the network config to this VM's MAC address. Replace
	# it with a systemd-networkd rule matching any ethernet device by name,
	# so the image works under any hypervisor. netplan goes away in stage 2.
	cat >/etc/systemd/network/80-workshop.network <<'NETWORK'
[Match]
Name=e*

[Network]
DHCP=yes

[Link]
RequiredForOnline=no
NETWORK
	systemctl enable systemd-networkd.service

	step "setting hostname and login banners"
	echo "$WORKSHOP_HOSTNAME" >/etc/hostname
	grep -q "[[:space:]]$WORKSHOP_HOSTNAME\$" /etc/hosts || echo "127.0.1.1 $WORKSHOP_HOSTNAME" >>/etc/hosts
	cat >>/etc/issue <<ISSUE
BPF-LSM workshop VM. Log in as: $WORKSHOP_USER / $WORKSHOP_PASSWORD

ISSUE
	cat >/etc/motd <<MOTD

  BPF-LSM workshop VM (user: $WORKSHOP_USER, password: $WORKSHOP_PASSWORD, sudo without password)

  Labs are ready in: $WORKSHOP_DIR/labs
  Start with: cd $WORKSHOP_DIR/labs

  This is a disposable teaching VM with public credentials.
  Do not expose it to a network you do not trust.

  If a BPF LSM program locks you out, power-cycle the VM: programs do not
  survive a reboot.

MOTD

	step "handing over to stage 2"
	cp "$0" "$FINALIZE"
	systemd-run --no-block --quiet --unit=workshop-finalize --collect \
		--property=After=cloud-final.service \
		/bin/sh "$FINALIZE" finalize
}

stage2() {
	step "removing cloud-init, netplan and their Python stack"
	# They have done their job. The locales package only holds data for
	# generating locales; the image uses the built-in C.UTF-8. Left installed, cloud-init would look for a
	# datasource on every boot, and unattended-upgrades would run apt in
	# the background during the workshop.
	apt_get purge cloud-init unattended-upgrades 'netplan*' 'python3*' locales
	purge_old_kernels
	apt_get autoremove --purge
	rm -rf /etc/cloud /var/lib/cloud /etc/netplan

	step "removing files a workshop VM does not need"
	slim_installed_files
	prune_kernel_modules
	update-initramfs -u

	step "recording package manifest"
	echo WORKSHOP-PACKAGES-BEGIN
	# shellcheck disable=SC2016  # dpkg-query format string, not a shell expansion
	dpkg-query -W -f='${binary:Package}\t${Version}\n'
	echo WORKSHOP-PACKAGES-END

	step "cleaning up"
	apt-get clean
	rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/man/* /var/cache/debconf/*-old
	rm -f /etc/ssh/ssh_host_*
	rm -f /var/lib/systemd/random-seed /var/lib/dbus/machine-id
	: >/etc/machine-id
	# Without this directory journald logs to memory only, which is plenty
	# for a workshop and keeps build-time logs out of the image.
	rm -rf /var/log/journal
	find /var/log -type f -exec truncate -s 0 {} +
	step "disk usage: $(df -m / | awk 'NR==2 {print $3}') MB"
	# Hand freed blocks back to the host so the compressed image stays small.
	fstrim -av || step "fstrim failed; the image will be larger than necessary"

	step "done"
	echo WORKSHOP-PROVISION-OK
	sync
	poweroff
}

case "${1:-}" in
finalize) stage2 ;;
*) stage1 ;;
esac
