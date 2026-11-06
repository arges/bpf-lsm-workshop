# Run the workshop VM

Log in with the user **`workshop`** and the password **`workshop`**. `sudo` needs no password.

Use this VM only for teaching. Its password is public. Keep it on NAT networking, which every
recipe below uses. Do not connect it to a network that you do not trust.

The image includes the workshop files. After login, start here:

```sh
cd ~/bpf-lsm-workshop/labs
rm -rf work && mkdir work && cd work
```

## 1. Download the image

Go to the Releases page of this project. Download the file for your computer, and download
`SHA256SUMS`.

| Your computer | File |
|---|---|
| Linux, Intel/AMD | `bpf-lsm-workshop-amd64.qcow2` |
| Mac, Apple silicon (M1 or later) | `bpf-lsm-workshop-arm64.utm.zip` (UTM) or `bpf-lsm-workshop-arm64.qcow2` (QEMU) |
| Mac, Intel | `bpf-lsm-workshop-amd64.qcow2` (QEMU) or `bpf-lsm-workshop-amd64.ova` (VirtualBox/VMware) |
| Windows, Intel/AMD | `bpf-lsm-workshop-amd64.ova` (VirtualBox/VMware), `bpf-lsm-workshop-amd64.vhdx.zip` (Hyper-V) or `bpf-lsm-workshop-amd64.qcow2` (QEMU) |

Check the download:

```sh
sha256sum --ignore-missing -c SHA256SUMS        # Linux
shasum -a 256 --ignore-missing -c SHA256SUMS    # macOS
```

On Windows, compare the output of this command with the line in `SHA256SUMS`:

```powershell
Get-FileHash .\bpf-lsm-workshop-amd64.ova -Algorithm SHA256
```

## 2. Start the VM

We tested only some of the methods below:

| Method | Status |
|---|---|
| Linux, QEMU/KVM, amd64 | **Tested.** `make test` builds and tests it. |
| arm64 image under QEMU emulation on an x86 Linux host | **Tested** with `make test ARCH=arm64`. |
| amd64 OVA disk on IDE and E1000 hardware under QEMU | **Tested.** It boots, gets a network, and passes the BPF LSM test. |
| OVA import into VirtualBox or VMware | **Not tested.** |
| macOS: the UTM bundle (`.utm.zip`) | **Not tested.** We wrote its settings from the UTM source code. Nobody opened it in UTM yet. |
| macOS: QEMU with HVF, or a manual UTM import | **Not tested.** |
| amd64 VHDX disk on IDE hardware under QEMU | **Tested.** It boots and passes the BPF LSM test and the lab tests. |
| Windows: Hyper-V or QEMU with WHPX | **Not tested.** |

If you try a method that we did not test, please tell us the result.

### Linux (QEMU/KVM)

1. Install QEMU: `apt install qemu-system-x86`, `dnf install qemu-kvm` or `pacman -S qemu-base`.
2. Make sure that your user can open `/dev/kvm`.
3. Start the VM:

   ```sh
   qemu-system-x86_64 -accel kvm -cpu host -m 2048 -smp 2 -nographic \
     -drive file=bpf-lsm-workshop-amd64.qcow2,if=virtio \
     -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22
   ```

The VM console uses your terminal. To stop QEMU, push `Ctrl-a` and then `x`. To connect with SSH,
open a second terminal:

```sh
ssh -p 2222 workshop@127.0.0.1
```

If you have a copy of this repository, use the headless SSH workflow instead:

```sh
make start
make ssh
make stop
```

`make start` waits for SSH before it returns. Use `make run` when you need the serial console. You
can also open the image as an existing disk in virt-manager or GNOME Boxes.

### macOS, Apple silicon

Use an **arm64** file. The amd64 image runs only in emulation on these Macs, and that is too slow.

**UTM (recommended)**

1. Install UTM from <https://mac.getutm.app> (free), or run `brew install --cask utm`.
2. Download `bpf-lsm-workshop-arm64.utm.zip`.
3. Double-click the zip file to unpack it.
4. Double-click `bpf-lsm-workshop.utm`. UTM imports the VM.
5. Push the play button. A terminal window opens and shows the login prompt.

You can also connect with SSH from a terminal on the Mac:

```sh
ssh -p 2222 workshop@127.0.0.1
```

Problems with UTM:

- If the VM does not start, open the VM settings in UTM. Look at the memory and CPU values under
  *System*.
- If port 2222 is in use on your Mac, change the forwarded port under *Network*.

**QEMU.** Install it with `brew install qemu`. Then run:

```sh
qemu-system-aarch64 -accel hvf -cpu host -machine virt -m 2048 -smp 2 -nographic \
  -bios "$(brew --prefix qemu)/share/qemu/edk2-aarch64-code.fd" \
  -drive file=bpf-lsm-workshop-arm64.qcow2,if=virtio \
  -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22
```

**UTM by hand.** Use these steps if UTM does not import the bundle:

1. Create a new VM. Select *Virtualize*, then *Other*.
2. Do not select a boot ISO.
3. Set the memory to 2 GB.
4. Open the settings of the new VM. Remove the empty drive that UTM made.
5. Select *New Drive*, then *Import*. Add `bpf-lsm-workshop-arm64.qcow2` as a VirtIO drive.

### macOS, Intel

```sh
qemu-system-x86_64 -accel hvf -cpu host -m 2048 -smp 2 -nographic \
  -drive file=bpf-lsm-workshop-amd64.qcow2,if=virtio \
  -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22
```

You can also import the OVA into VirtualBox or VMware Fusion. The Windows section shows how.

### Windows

**VirtualBox or VMware Workstation**

1. Import `bpf-lsm-workshop-amd64.ova`. In VirtualBox, use *File → Import Appliance*. In VMware,
   use *File → Open*.
2. VMware can show a warning that the appliance does not pass the OVF specification checks. If it
   does, select *Retry*.
3. Start the VM. Log in on its console.

To use SSH from Windows with VirtualBox, forward a port before you start the VM:

```powershell
VBoxManage modifyvm bpf-lsm-workshop --natpf1 "ssh,tcp,127.0.0.1,2222,,22"
ssh -p 2222 workshop@127.0.0.1
```

**QEMU for Windows.** Get it from <https://www.qemu.org/download/#windows>. Turn on the
*Windows Hypervisor Platform* feature. Then run:

```powershell
qemu-system-x86_64 -accel whpx -m 2048 -smp 2 `
  -drive file=bpf-lsm-workshop-amd64.qcow2,if=virtio `
  -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22
```

**Hyper-V**

Hyper-V is in Windows Pro, Enterprise and Education. It is not in Windows Home. To turn it on, run
this command in PowerShell as administrator, and then restart Windows:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
```

1. Unpack `bpf-lsm-workshop-amd64.vhdx.zip`. You get `bpf-lsm-workshop-amd64.vhdx`. Put it in
   the folder where you want to keep the VM.
2. Run these commands in PowerShell as administrator, in the same folder:

   ```powershell
   New-VM -Name bpf-lsm-workshop -Generation 1 -MemoryStartupBytes 2GB `
     -VHDPath "$PWD\bpf-lsm-workshop-amd64.vhdx" -SwitchName "Default Switch"
   Set-VMProcessor -VMName bpf-lsm-workshop -Count 2
   Start-VM -Name bpf-lsm-workshop
   vmconnect localhost bpf-lsm-workshop
   ```

   Or use Hyper-V Manager: select *New → Virtual Machine*. Select *Generation 1*, 2048 MB of memory
   and the *Default Switch*. Then select *Use an existing virtual hard disk* and the `.vhdx` file.
3. Log in on the console. Get the IP address of the VM:

   ```sh
   hostname -I
   ```

4. To use SSH from Windows, use that address:

   ```powershell
   ssh workshop@<address>
   ```

Use *Generation 1*. It boots without UEFI, so Secure Boot does not apply. If you use
*Generation 2*, open *Settings → Security* and select the *Microsoft UEFI Certificate Authority*
template, or clear *Enable Secure Boot*. The default template does not start Linux.

The *Default Switch* can give the VM a different address after Windows restarts. If SSH stops
working, run `hostname -I` again.

**VirtualBox and Hyper-V together.** If Hyper-V, WSL2 or *Memory integrity* is on, VirtualBox runs
on top of Hyper-V. Then VirtualBox is slow, or the VM does not start. In this case, use the
Hyper-V image or VMware.

## 3. Check the VM

Run these commands inside the VM:

```sh
cat /sys/kernel/security/lsm      # the list must contain "bpf"
clang --version
sudo bpftool prog show
```

## Convert to other formats

`qemu-img convert` changes the qcow2 file into other formats:

```sh
qemu-img convert -O vdi   bpf-lsm-workshop-amd64.qcow2 bpf-lsm-workshop-amd64.vdi    # VirtualBox
qemu-img convert -O vmdk  bpf-lsm-workshop-amd64.qcow2 bpf-lsm-workshop-amd64.vmdk   # VMware
qemu-img convert -O vhdx  bpf-lsm-workshop-amd64.qcow2 bpf-lsm-workshop-amd64.vhdx   # Hyper-V
qemu-img convert -O raw   bpf-lsm-workshop-amd64.qcow2 bpf-lsm-workshop-amd64.img
```

The converted files are not compressed. Each file uses 2–3 GB.

## Troubleshooting

- **`Could not access KVM kernel module`** (Linux). Add your user to the `kvm` group and log in
  again. Or replace `-accel kvm -cpu host` with `-accel tcg -cpu max`. The second option is slow.
- **Port 2222 is in use.** Change `2222` in the `hostfwd=` option and in the `ssh` command.
- **A BPF LSM program locked you out.** Stop the VM and start it again. A reboot removes all loaded
  programs, unless you made a program persistent.
- **`apt install` finds no packages.** The image has no package lists, to save space. Run
  `sudo apt update` first.
