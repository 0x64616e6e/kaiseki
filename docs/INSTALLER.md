# The kaiseki installer

Boot the ISO, choose the disk, and that is the only decision before the system is running:

1. Boot the ISO.
2. Choose the disk (and confirm that it will be erased).
3. Install, unattended: **59 seconds** in the test VM.
4. The installed system starts **without a reboot**, on the kernel that is already running.
5. Omarchy's own first-boot setup asks for keyboard, account, host name and time zone.
6. It creates the owner, moves the disk encryption to the owner's password, and opens the desktop.

Status (2026-10-06): works end to end in a virtual machine on Debian testing, `tests/run-installer` passes,
including a cold boot from the disk afterwards. Not tried on real hardware.

| | |
|---|---|
| 1. Choose the disk ![](img/installer/1-choose-disk.png) | 2. Confirm ![](img/installer/2-confirm-erase.png) |
| 3. Installed system, same kernel: upstream's setup ![](img/installer/3-first-boot.png) | 4. Keyboard ![](img/installer/4-keyboard.png) |
| 5. Account, host name, time zone ![](img/installer/5-confirm.png) | 6. Setting up ![](img/installer/6-setting-up.png) |
| 7. Desktop ![](img/installer/7-desktop.png) | 8. Later cold boots: one passphrase prompt ![](img/installer/8-cold-boot-passphrase.png) |

## How it is built

| Piece | What it does |
|---|---|
| `installer/build-root.sh` | On a build machine: bootstrap Debian into a ZFS dataset, add kernel, ZFS, firmware and Omarchy's whole package set through the shim, export as a compressed ZFS stream (7.1 GB installed, 2.4 GB stream). Nothing machine-specific. |
| `installer/build-iso.sh` | A small Debian live system (same kernel package and ZFS as the image) carrying the stream, ZFSBootMenu and the installer, which starts on tty1. 3.9 GB. |
| `installer/install.sh` | The install itself, below. |
| `shims/cryptsetup`, `shims/limine-update` | Let upstream's first-boot setup re-key a ZFS pool and rebuild a Debian initramfs while it believes it is re-keying LUKS and updating Limine. |

## What the 59 seconds are

| Step | Time | What |
|---|---|---|
| Partitioning | 3 s | GPT: 1 GB EFI system partition, the rest one ZFS partition. |
| Encrypted pool | <1 s | `rpool`, AES-256-GCM, with a random throwaway passphrase. |
| Laying down the system | 32 s | `zfs receive` of the prepared root into `rpool/ROOT/kaiseki`; `rpool/home`. |
| Making it this machine | 1 s | Host id, machine id, ssh host keys, fstab for the ESP. |
| System setup | 8 s | Upstream's `omarchy-apply-system --defer-provisioning --first-install` in the target, so its hardware fixes see the real machine. |
| Arming first boot | <1 s | Upstream's `omarchy-provision-owner.service` and its `pending` flag, as its own ISO does. |
| Boot loader | 13 s | Initramfs for this machine; ZFSBootMenu on the ESP with an EFI boot entry and the fallback path. |
| Verifying | 1 s | Kernel, initramfs (ZFS module and key inside), boot loader, `bootfs`, key; snapshot `@installed`. |

## No reboot

`systemctl soft-reboot`: systemd shuts the live system's userspace down and starts the installed one from
`/run/nextroot`, on the same kernel. The pool is created without an alternate root and the root dataset is
mounted with `-o zfsutil`, so the pool is already in its final shape at the hand-over. The test confirms it:
one boot in the journal, and the kernel command line is still the live ISO's.

The installed system has then never booted from its own disk, so the installer verifies what a cold boot
needs before handing over, and `tests/run-installer` powers the machine off and boots it from the disk alone.
If the live kernel ever differs from the image's, the installer falls back to `kexec` into the installed kernel.

## Encryption without an early question

The pool is encrypted from the first byte with a throwaway passphrase. First-boot setup then asks for the
owner's password and re-keys the pool to it; `zfs change-key` is instant and rewrites no data. Upstream's
setup does this for LUKS; `shims/cryptsetup` answers the same calls for ZFS.

One passphrase prompt per boot: ZFSBootMenu asks, and the initramfs (which lives inside the encrypted pool)
carries the key file so the kernel's own import does not ask again. As on Omarchy, an encrypted machine
then logs the owner in automatically: the disk passphrase is the authentication.

ZFS wants at least 8 characters. Upstream's form accepts shorter passwords; with one, the re-key step fails
loudly and offers a retry.

## Decisions taken, and open

- **Debian testing is the base** for the image (see README). The same scripts work on Debian 13 once the
  backports selection there is finished (`packages/backports-pins`).
- **ZFSBootMenu** (pinned release image, checksum verified). Boot environments are selectable at boot, the
  closest match to Omarchy's snapshot menu. The pool is created with `compatibility=openzfs-2.2-linux` so
  ZFSBootMenu's own ZFS can always read it.
- **Whole disk only.** No dual boot yet.
- **No Secure Boot.** ZFS is an out-of-tree module and ZFSBootMenu is unsigned; enrolling keys cannot be unattended.
- **Interrupted between install and setup:** the throwaway passphrase exists only in the installed system,
  so a power cut in that window means installing again (one minute). Upstream embeds an auto-unlock key instead.
- Not done: the factory-reset snapshot Omarchy offers; the console font upstream uses for its logo (some
  glyphs show as `#`); a styled disk chooser; Wi-Fi during setup (nothing in the install needs the network,
  first-boot setup fetches Node.js if it can).
- The 22 upstream packages kaiseki cannot build yet are missing from the image as they are from the tests.

## Building and testing

```
# on a Debian testing build machine that has the kaiseki repository (tests/run leaves one behind)
installer/build-root.sh        # -> /srv/kaiseki/image/root.zfs.zst, manifest      (about 25 minutes)
installer/build-iso.sh         # -> /srv/kaiseki/image/kaiseki-TAG.iso             (about 11 minutes)

# on the host, with the ISO, its kernel and initrd in .cache/iso/
tests/run-installer NAME       # empty VM: install, first-boot form by key presses, cold boot; PASS or FAIL
vm/vm view NAME                # watch it
```

Unattended installs for tests: the kernel arguments `kaiseki.disk=/dev/vda` (answers the one question) and
`kaiseki.enter=soft-reboot|kexec|reboot|none`.
