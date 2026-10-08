#!/bin/sh
# Package a workshop qcow2 image as an OVA for VirtualBox and VMware.
#
#   scripts/make-ova.sh <image.qcow2> <output.ova>
#
# The appliance describes deliberately boring hardware that both products
# emulate without guest drivers: BIOS firmware, an IDE disk and an Intel
# E1000 network card on NAT.
set -eu
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

[ $# -eq 2 ] || die "usage: $0 <image.qcow2> <output.ova>"
image=$1
ova=$2

need qemu-img tar sha256sum
[ -f "$image" ] || die "image not found: $image"

name=$(basename "$ova" .ova)
vm_name=bpf-lsm-workshop
cpus=${OVA_CPUS:-2}
mem_mb=${OVA_MEM:-2048}

work=$(dirname "$ova")/ova-work
rm -rf "$work" "$ova.tmp"
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

echo "converting to stream-optimized VMDK"
qemu-img convert -O vmdk -o subformat=streamOptimized "$image" "$work/$name.vmdk"

capacity=$(qemu-img info "$image" | sed -n 's/^virtual size:.*(\([0-9]*\) bytes).*/\1/p')
[ -n "$capacity" ] || die "could not determine the virtual size of $image"
vmdk_size=$(wc -c <"$work/$name.vmdk" | tr -d ' ')

# Children of each <Item> are in alphabetical order, as OVF 1.0 requires.
cat >"$work/$name.ovf" <<OVF
<?xml version="1.0" encoding="UTF-8"?>
<Envelope ovf:version="1.0" xml:lang="en-US"
    xmlns="http://schemas.dmtf.org/ovf/envelope/1"
    xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1"
    xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData"
    xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <References>
    <File ovf:href="$name.vmdk" ovf:id="file1" ovf:size="$vmdk_size"/>
  </References>
  <DiskSection>
    <Info>Virtual disks</Info>
    <Disk ovf:capacity="$capacity" ovf:diskId="vmdisk1" ovf:fileRef="file1" ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized"/>
  </DiskSection>
  <NetworkSection>
    <Info>Logical networks</Info>
    <Network ovf:name="NAT">
      <Description>NAT network</Description>
    </Network>
  </NetworkSection>
  <VirtualSystem ovf:id="$vm_name">
    <Info>BPF-LSM workshop VM (login: workshop / workshop)</Info>
    <Name>$vm_name</Name>
    <OperatingSystemSection ovf:id="96">
      <Info>The guest operating system</Info>
      <Description>Debian GNU/Linux (64-bit)</Description>
    </OperatingSystemSection>
    <VirtualHardwareSection>
      <Info>Virtual hardware requirements</Info>
      <System>
        <vssd:ElementName>Virtual Hardware Family</vssd:ElementName>
        <vssd:InstanceID>0</vssd:InstanceID>
        <vssd:VirtualSystemIdentifier>$vm_name</vssd:VirtualSystemIdentifier>
        <vssd:VirtualSystemType>vmx-14</vssd:VirtualSystemType>
      </System>
      <Item>
        <rasd:Caption>$cpus virtual CPU(s)</rasd:Caption>
        <rasd:Description>Number of virtual CPUs</rasd:Description>
        <rasd:ElementName>$cpus virtual CPU(s)</rasd:ElementName>
        <rasd:InstanceID>1</rasd:InstanceID>
        <rasd:ResourceType>3</rasd:ResourceType>
        <rasd:VirtualQuantity>$cpus</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:AllocationUnits>MegaBytes</rasd:AllocationUnits>
        <rasd:Caption>$mem_mb MB of memory</rasd:Caption>
        <rasd:Description>Memory Size</rasd:Description>
        <rasd:ElementName>$mem_mb MB of memory</rasd:ElementName>
        <rasd:InstanceID>2</rasd:InstanceID>
        <rasd:ResourceType>4</rasd:ResourceType>
        <rasd:VirtualQuantity>$mem_mb</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:Address>0</rasd:Address>
        <rasd:Caption>ideController0</rasd:Caption>
        <rasd:Description>IDE Controller</rasd:Description>
        <rasd:ElementName>ideController0</rasd:ElementName>
        <rasd:InstanceID>3</rasd:InstanceID>
        <rasd:ResourceType>5</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:Caption>disk1</rasd:Caption>
        <rasd:Description>Disk Image</rasd:Description>
        <rasd:ElementName>disk1</rasd:ElementName>
        <rasd:HostResource>ovf:/disk/vmdisk1</rasd:HostResource>
        <rasd:InstanceID>4</rasd:InstanceID>
        <rasd:Parent>3</rasd:Parent>
        <rasd:ResourceType>17</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Caption>Ethernet adapter on 'NAT'</rasd:Caption>
        <rasd:Connection>NAT</rasd:Connection>
        <rasd:Description>E1000 ethernet adapter on NAT</rasd:Description>
        <rasd:ElementName>Ethernet adapter on 'NAT'</rasd:ElementName>
        <rasd:InstanceID>5</rasd:InstanceID>
        <rasd:ResourceSubType>E1000</rasd:ResourceSubType>
        <rasd:ResourceType>10</rasd:ResourceType>
      </Item>
    </VirtualHardwareSection>
  </VirtualSystem>
</Envelope>
OVF

(
	cd "$work"
	for f in "$name.ovf" "$name.vmdk"; do
		echo "SHA256($f)= $(sha256sum "$f" | cut -d' ' -f1)"
	done >"$name.mf"
)

# The descriptor must be the first member of the archive.
tar --format=ustar -cf "$ova.tmp" -C "$work" "$name.ovf" "$name.mf" "$name.vmdk"
mv "$ova.tmp" "$ova"
echo "built $ova ($(du -h "$ova" | cut -f1))"
