#!/bin/sh
# Package the arm64 workshop image as a UTM virtual machine for Apple silicon
# Macs (https://mac.getutm.app).
#
#   scripts/make-utm.sh <image-arm64.qcow2> <output.utm.zip>
#
# A UTM VM is a directory named <something>.utm containing config.plist and a
# Data/ directory with the disk image. The configuration below follows UTM's
# QEMU backend format, configuration version 4 (UTM 4.x), as defined in the
# Configuration/ directory of https://github.com/utmapp/UTM.
set -eu
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

[ $# -eq 2 ] || die "usage: $0 <image-arm64.qcow2> <output.utm.zip>"
image=$1
out=$2

need zip
[ -f "$image" ] || die "image not found: $image"

vm_name=bpf-lsm-workshop
disk_name=$(basename "$image")
cpus=${UTM_CPUS:-2}
mem_mb=${UTM_MEM:-2048}
ssh_port=${UTM_SSH_PORT:-2222}

outdir=$(cd "$(dirname "$out")" && pwd)
out=$outdir/$(basename "$out")
work=$outdir/utm-work
bundle=$work/$vm_name.utm
rm -rf "$work" "$out.tmp"
mkdir -p "$bundle/Data"
trap 'rm -rf "$work"' EXIT

cp "$image" "$bundle/Data/$disk_name"

# Serial console only (no display): the VM opens in a terminal window showing
# the login prompt. Networking is UTM's user-mode "Emulated VLAN" so that the
# guest's SSH port can be forwarded to the Mac's loopback address.
cat >"$bundle/config.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Backend</key>
	<string>QEMU</string>
	<key>ConfigurationVersion</key>
	<integer>4</integer>
	<key>Information</key>
	<dict>
		<key>Name</key>
		<string>$vm_name</string>
		<key>Icon</key>
		<string>linux</string>
		<key>IconCustom</key>
		<false/>
		<key>Notes</key>
		<string>BPF-LSM workshop VM. Log in as workshop / workshop. SSH: ssh -p $ssh_port workshop@127.0.0.1</string>
		<key>UUID</key>
		<string>6B1E0F1C-5D0B-4C53-9A52-B9F1C0DE0001</string>
	</dict>
	<key>System</key>
	<dict>
		<key>Architecture</key>
		<string>aarch64</string>
		<key>Target</key>
		<string>virt</string>
		<key>CPU</key>
		<string>default</string>
		<key>CPUFlagsAdd</key>
		<array/>
		<key>CPUFlagsRemove</key>
		<array/>
		<key>CPUCount</key>
		<integer>$cpus</integer>
		<key>ForceMulticore</key>
		<false/>
		<key>MemorySize</key>
		<integer>$mem_mb</integer>
		<key>JITCacheSize</key>
		<integer>0</integer>
	</dict>
	<key>QEMU</key>
	<dict>
		<key>DebugLog</key>
		<false/>
		<key>UEFIBoot</key>
		<true/>
		<key>RNGDevice</key>
		<true/>
		<key>BalloonDevice</key>
		<false/>
		<key>TPMDevice</key>
		<false/>
		<key>Hypervisor</key>
		<true/>
		<key>RTCLocalTime</key>
		<false/>
		<key>PS2Controller</key>
		<false/>
		<key>AdditionalArguments</key>
		<array/>
	</dict>
	<key>Input</key>
	<dict>
		<key>UsbBusSupport</key>
		<string>3.0</string>
		<key>UsbSharing</key>
		<false/>
		<key>MaximumUsbShare</key>
		<integer>3</integer>
	</dict>
	<key>Sharing</key>
	<dict>
		<key>DirectoryShareMode</key>
		<string>None</string>
		<key>DirectoryShareReadOnly</key>
		<false/>
		<key>ClipboardSharing</key>
		<false/>
	</dict>
	<key>Display</key>
	<array/>
	<key>Drive</key>
	<array>
		<dict>
			<key>ImageName</key>
			<string>$disk_name</string>
			<key>ImageType</key>
			<string>Disk</string>
			<key>Interface</key>
			<string>VirtIO</string>
			<key>InterfaceVersion</key>
			<integer>1</integer>
			<key>Identifier</key>
			<string>6B1E0F1C-5D0B-4C53-9A52-B9F1C0DE0002</string>
			<key>ReadOnly</key>
			<false/>
		</dict>
	</array>
	<key>Network</key>
	<array>
		<dict>
			<key>Mode</key>
			<string>Emulated</string>
			<key>Hardware</key>
			<string>virtio-net-pci</string>
			<key>MacAddress</key>
			<string>52:54:00:B9:F1:C0</string>
			<key>IsolateFromHost</key>
			<false/>
			<key>PortForward</key>
			<array>
				<dict>
					<key>Protocol</key>
					<string>TCP</string>
					<key>HostAddress</key>
					<string>127.0.0.1</string>
					<key>HostPort</key>
					<integer>$ssh_port</integer>
					<key>GuestPort</key>
					<integer>22</integer>
				</dict>
			</array>
		</dict>
	</array>
	<key>Serial</key>
	<array>
		<dict>
			<key>Mode</key>
			<string>Terminal</string>
			<key>Target</key>
			<string>Auto</string>
			<key>Terminal</key>
			<dict>
				<key>Font</key>
				<string>Menlo</string>
				<key>FontSize</key>
				<integer>12</integer>
				<key>CursorBlink</key>
				<true/>
			</dict>
		</dict>
	</array>
	<key>Sound</key>
	<array/>
</dict>
</plist>
PLIST

# The disk image is already compressed, so store rather than deflate.
(cd "$work" && zip -q -r -0 "$out.tmp" "$vm_name.utm")
mv "$out.tmp" "$out"
echo "built $out ($(du -h "$out" | cut -f1))"
