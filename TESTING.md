# Phase 1 test checklist

## Mouse and keyboard at each stage

The GRUB and ISOLINUX boot menus are keyboard-only. Neither bootloader
supports a mouse, on real PCs or in VMs. So that stage tests the keyboard.

| Stage | What to check | VBox BIOS | VBox EFI | Real PC |
|---|---|---|---|---|
| 1. Boot menu | arrow keys move the highlight, Enter boots | [ ] | [ ] | [ ] |
| 2. Live login | desktop appears without a login prompt | [ ] | [ ] | [ ] |
| 3. Live session | pointer follows the host cursor with no capture (VM); USB mouse moves, clicks, right-click menu works, wheel scrolls in Dolphin | [ ] | [ ] | [ ] |
| 3b. Touchpad | one-finger tap = click, two-finger scroll (laptops only) | — | — | [ ] |
| 3c. Keyboard | type in Konsole; `Ctrl+Alt+T` or the menu opens apps | [ ] | [ ] | [ ] |
| 4. Installer | double-click "Install Aurora OS"; all buttons/dropdowns work with the mouse; keyboard-layout test field accepts typing | [ ] | [ ] | [ ] |
| 5. Installed system | after reboot (ISO removed): SDDM login screen accepts mouse clicks and the password; desktop mouse works | [ ] | [ ] | [ ] |

Useful commands in Konsole:

```bash
sudo libinput list-devices | grep -A1 Device   # every input device the desktop sees
lsmod | grep -E 'usbhid|hid_generic|psmouse'  # HID drivers loaded
systemd-detect-virt                            # "oracle" inside VirtualBox
lsinitramfs /boot/initrd.img-$(uname -r) | grep -E 'usbhid|hid-generic'  # installed system: early drivers present
```

## Boot and install matrix

- [ ] VirtualBox, EFI off (BIOS): live session boots
- [ ] VirtualBox, EFI off (BIOS): install completes, reboots into the installed system
- [ ] VirtualBox, EFI on: live session boots
- [ ] VirtualBox, EFI on: install completes, reboots into the installed system
- [ ] VirtualBox, EFI on + Secure Boot on: live and installed system both boot (`mokutil --sb-state` says "SecureBoot enabled")
- [ ] Real PC, UEFI + Secure Boot: USB boots, install completes
- [ ] Real PC, legacy BIOS/CSM: USB boots
- [ ] Installed system: `ls /boot/efi/EFI` shows `debian` and `BOOT` (UEFI only)
- [ ] Installed system: `dpkg -l | grep -E 'live-boot|calamares'` prints nothing (live packages removed)
- [ ] Installed system: Wi-Fi networks listed (real PC)
