# Aurora OS build kit — Phase 1

This is Phase 1: a bootable hybrid ISO based on Debian 13 (trixie) with a
minimal KDE Plasma 6 live session, the Calamares installer and working USB
mouse, keyboard and touchpad input. It boots BIOS and UEFI, including Secure
Boot. Phase 2 adds the Windows 11-style desktop, Phase 3 adds the boot menu,
splash and branding polish, and Phase 4 covers the full test and
troubleshooting guide.

To rename the OS, edit `os.conf` and rebuild. No other file needs changing.

## Folder tree

```
aurora-os-kit/
├── build.sh                 one command: tools → package check → clean → build → out/*.iso
├── check-packages.sh        checks every listed package exists in Debian 13
├── os.conf                  OS name / id / version / live user / options
├── README.md                this guide
├── TESTING.md               tick-off checklist for Phase 1
├── tools/
│   ├── render.py            fills @@TOKENS@@ from os.conf into build/
│   └── make-branding.py     draws the original installer artwork (PNG)
└── config-src/              copied to build/ on every run, then rendered
    ├── auto/
    │   ├── config           all live-build options (lb config)
    │   ├── build            lb build wrapper
    │   └── clean            lb clean wrapper
    └── config/
        ├── package-lists/
        │   ├── 10-live-installer.list.chroot   live system, Calamares, GRUB/shim pieces
        │   ├── 20-firmware.list.chroot         Wi-Fi/GPU/sound firmware, microcode
        │   ├── 30-input.list.chroot            libinput, Xorg input
        │   └── 40-desktop-minimal.list.chroot  minimal Plasma 6 (grown in Phase 2)
        ├── hooks/normal/
        │   ├── 0200-virtualbox-guest.hook.chroot      VirtualBox guest utils (optional, fail-soft)
        │   ├── 0300-installer-grub-debs.hook.chroot   stores grub-pc + grub-efi-amd64 for the installer
        │   ├── 0400-live-services.hook.chroot         enables live setup service
        │   └── 9000-initramfs.hook.chroot             rebuilds initramfs with early input drivers
        └── includes.chroot/                           files copied into the image as-is
            ├── etc/X11/xorg.conf.d/40-@@OS_ID@@-touchpad.conf   tap-to-click (X11)
            ├── etc/xdg/autostart/@@OS_ID@@-touchpad-tap.desktop  tap-to-click (Wayland)
            ├── etc/systemd/system/@@OS_ID@@-live-setup.service   live-only setup
            ├── etc/calamares/settings.conf                        installer page/job order
            ├── etc/calamares/branding/@@OS_ID@@/branding.desc     installer branding
            ├── etc/calamares/modules/*.conf                       one file per installer step
            ├── usr/bin/@@OS_ID@@-install                          starts the installer as root
            ├── usr/lib/@@OS_ID@@-installer/
            │   ├── live-setup        autologin, polkit, desktop icon (live only)
            │   ├── target-prepare    installs BIOS or UEFI GRUB into the new system
            │   ├── target-cleanup    Secure Boot fallback + removes live-only files
            │   └── touchpad-tap      enables tap-to-click on Wayland
            ├── usr/share/applications/@@OS_ID@@-install.desktop
            ├── usr/local/share/applications/calamares.desktop      hides duplicate menu entry
            └── usr/share/initramfs-tools/modules.d/@@OS_ID@@-input HID/USB/touchpad drivers in initramfs
```

`@@OS_ID@@` in a name becomes `aurora` (your `OS_ID`) when the kit is built.

## How the pieces fit

- **Boot:** BIOS PCs boot through ISOLINUX and UEFI PCs through GRUB.
  For Secure Boot, live-build uses Debian's Microsoft-signed `shim` and
  Debian-signed GRUB (`--uefi-secure-boot enable`). The ISO is a hybrid
  image, so the same file works on a DVD or written raw to a USB stick.
- **Installer:** the kit uses its own Calamares sequence instead of
  `calamares-settings-debian`. Debian's sequence fetches GRUB from a package
  pool on the ISO, and this kit doesn't build that pool. Instead, hook 0300
  stores both GRUB variants inside the image. `target-prepare` installs the
  one that matches how the PC booted. Calamares then runs Debian's
  `grub-install`, which places shim and signed GRUB under `\EFI\debian\`.
  `target-cleanup` copies them to `\EFI\BOOT\BOOTX64.EFI`, so Secure Boot
  still works if the firmware loses its boot entry.
- **Input:** USB controller and HID drivers (`usbhid`, `hid_generic`,
  `hid_multitouch`, `psmouse`, `i2c_hid_acpi`, ...) are loaded from the
  initramfs. The desktop uses libinput, and tap-to-click is on for both X11
  and Wayland.
- **Live session:** `live-setup` runs only when the kernel command line
  contains `boot=live`. It sets up autologin and passwordless installer
  access, and puts an "Install Aurora OS" icon on the desktop. None of this
  ends up on an installed system. In VirtualBox the live session uses
  Plasma X11, where the guest tools work best. On real hardware it uses
  Plasma Wayland.

---

## Step-by-step

### a. Set up the build machine

Use a Debian 13 VM in VirtualBox (or any Debian 13 PC):

| Setting  | Value |
|----------|-------|
| ISO      | `debian-13.x.x-amd64-netinst.iso` from debian.org |
| RAM      | 4 GB minimum, 8 GB recommended |
| CPUs     | 2 or more |
| Disk     | **60 GB** dynamically allocated (each build uses ~25 GB) |
| Software | During install, choose "SSH server" + "standard system utilities" (a desktop is optional) |

After installing, copy the kit into the VM, for example with `scp -r aurora-os-kit user@vm:`,
or download the `.tar.gz` and extract it:

```bash
tar xzf aurora-os-kit-phase1.tar.gz
cd aurora-os-kit
```

The path must not contain spaces.

### b. Build the ISO

```bash
sudo ./build.sh
```

The first run installs live-build and the other tools. It then checks
every package name against Debian 13, with output like `ok`/`MISSING` per
package, and builds the ISO. The finished ISO is
`out/aurora-1.0-amd64.iso` with a `.sha256` file beside it, and the full
log is in `logs/`.

- **Expected size:** about 2.5–3.5 GB. Firmware and Plasma make up most
  of it.
- **Expected time:** the first build takes 30–90 minutes, depending on
  internet speed and CPU. Re-runs are faster because downloaded packages
  are kept in `.lb-cache/`.
- **Re-running:** every run cleans and rebuilds from scratch.
  `sudo ./build.sh --clean` removes `build/` only, and `--purge-cache`
  also deletes the download cache.
- **Checking packages only:** run `./check-packages.sh`, or
  `./check-packages.sh some-package` for a single name.

### c. VirtualBox test VM

Create a new VM. Leave "ISO image" empty in the wizard, or uncheck
"Unattended install", so VirtualBox doesn't try to auto-install it.

| Setting | Value | Why |
|---|---|---|
| Type / Version | Linux / Debian (64-bit) | |
| RAM | 4096 MB (3072 minimum) | Plasma + installer |
| CPUs | 2+ | |
| Disk | 32 GB VDI | installer requires 20 GB |
| System → Motherboard → **Enable EFI** | **off** for the BIOS test, **on** for the EFI test | make one VM of each, or toggle between tests |
| System → Motherboard → Secure Boot (VirtualBox 7+) | on for the Secure Boot test (EFI only) | press "Reset Keys to Default" once, which enrolls the Microsoft keys that Debian's shim is signed with |
| System → Motherboard → **Pointing Device** | **USB Tablet** | see below |
| Display → Video Memory | 128 MB | |
| Display → **Graphics Controller** | **VMSVGA** | kernel driver `vmwgfx`, best supported by Linux |
| Display → 3D acceleration | off for the first tests | rules out graphics issues |
| USB → **USB controller** | USB 3.0 (xHCI); use USB 1.1 (OHCI) if 3.0 is greyed out | the tablet works on any of them |
| Storage → Optical drive | `out/aurora-1.0-amd64.iso` | |

**Why USB Tablet:** a PS/2 mouse sends only relative movements, so
VirtualBox has to "capture" the pointer inside the window, and you need the
Host key to escape. A USB Tablet reports absolute positions, as a
touchscreen or graphics tablet does. The guest's pointer then lands exactly
under your host cursor and moves in and out of the window freely. This
works through the plain kernel `usbhid` driver with no guest additions,
from the first second of the live session.

If the VirtualBox guest utilities were installed during the build (hook
0200 prints `I: VirtualBox guest utilities installed`), you also get
automatic screen resize and a shared clipboard. Turn the clipboard on with
Devices → Shared Clipboard → Bidirectional. If the build printed
`W: VirtualBox guest utilities NOT installed`, Debian's fasttrack repo has
no trixie build yet. Everything else still works, and you can set the
resolution in System Settings → Display.

### d. Write a USB stick and boot a real PC (quick version, more in Phase 4)

- **Windows:** use Rufus. Select the ISO, and when it asks, choose
  **"Write in DD Image mode"**. balenaEtcher also works.
- **macOS:** use balenaEtcher, or run `diskutil list`, then
  `diskutil unmountDisk /dev/diskN`, then
  `sudo dd if=aurora-1.0-amd64.iso of=/dev/rdiskN bs=4m`.
- **Linux:** run `lsblk` to find the stick, then
  `sudo dd if=out/aurora-1.0-amd64.iso of=/dev/sdX bs=4M status=progress conv=fsync`.
  Double-check `sdX`, because this wipes that disk.
- **Boot menu keys:** F12 (Dell, Lenovo, Acer), F11 (MSI, ASRock), F8 (ASUS),
  F9 (HP), Esc (some HP and ASUS), Option/Alt (Intel Macs).
- **Secure Boot:** it can stay **on**. The ISO uses Debian's
  Microsoft-signed shim. A few PCs, mostly newer Lenovo and Microsoft
  Surface, ship with the "Microsoft 3rd-party UEFI CA" disabled. In that
  case, enable "Allow Microsoft 3rd party UEFI CA" in the firmware setup.

### e. Troubleshooting (Phase 1 essentials)

| Symptom | Fix |
|---|---|
| Build stops with `E: Unable to locate package X` | run `./check-packages.sh`, then remove or rename X in `config-src/config/package-lists/` |
| Build interrupted, next run complains about mounts | just run `sudo ./build.sh` again; it unmounts leftovers. Rebooting the build VM also works |
| `No ISO was produced` | open the newest file in `logs/` and search for the first line starting with `E:` |
| Black screen after the boot menu (VM) | Graphics Controller must be VMSVGA with 3D off; give it 128 MB VRAM |
| Black screen on a real PC (NVIDIA) | at the boot menu press `e` (GRUB) or `Tab` (ISOLINUX) and add `nomodeset` to the kernel line |
| No mouse in the VM / pointer is "captured" | Pointing Device = USB Tablet, and a USB controller must be enabled |
| No mouse on a real PC | try another USB port (USB 2 ports avoid rare xHCI quirks). In a terminal: `sudo libinput list-devices` should list it |
| No Wi-Fi | `sudo dmesg | grep -i firmware` names the missing firmware file; `apt-file search <name>` names its package, which you then add to `20-firmware.list.chroot` |
| `Verification failed` / `bad shim signature` | Secure Boot is rejecting the signature: see the note in section d, or turn Secure Boot off temporarily |
| Installer says "not enough space" | the VM disk must be at least 20 GB |
| Installer fails at "shellprocess" | the full log is in `~/.cache/calamares/session.log` in the live session; send me the last 50 lines |

## Package names I couldn't verify from here

`check-packages.sh` checks all of these against Debian's archive before
every build. These are the ones I'm least sure about for Debian 13:

- `firmware-linux-nonfree`, `firmware-misc-nonfree`: Debian 13 split
  some firmware into new packages such as `firmware-intel-graphics` and
  `firmware-mediatek`. The two old names should still exist, but verify
  with `./check-packages.sh firmware-misc-nonfree firmware-intel-graphics`.
- `virtualbox-guest-utils` / `virtualbox-guest-x11`: these are not in
  Debian 13 itself. Hook 0200 installs them only if the fasttrack repo
  has them.
- The Plasma X11 session file `plasmax11.desktop`. If it's missing, the
  live session uses Wayland, and the mouse works either way.
