# The kaiseki installer (design)

Requested flow (2026-10-06):

1. Boot the ISO.
2. Choose the disk. Nothing else is asked.
3. Install, unattended.
4. Enter the installed system **without a reboot**: stay on the running kernel.
5. The operator sets up the account (name, password, keyboard, host name, time zone).
6. Finalize.

## How each step can work on Debian

**ISO.** A Debian live image built with the same kernel package, ZFS module and kaiseki package set that
gets installed. Sameness matters for step 4.

**Disk only.** Everything else has a default: GPT with an EFI system partition and one ZFS pool; root on
ZFS with a boot environment layout. Questions that normally come before the install move to step 5.

**Install.** Not a package-by-package install. The ISO carries a prepared root file system as a ZFS
stream; installing is `zfs receive` onto the new pool plus boot-loader setup. This is what makes
Omarchy's sub-minute installs possible, and ZFS does it natively.

**No reboot.** Two mechanisms, both in Debian 13 (systemd 257):

- `systemctl soft-reboot`: userspace is restarted with the installed root (`/run/nextroot`) while the
  kernel keeps running. Truly the same kernel, a few seconds. Needs the installed system's modules to
  match the running kernel, which the ISO guarantees.
- `kexec` into the installed kernel and initramfs: the kernel is replaced without going through the
  firmware. Slightly slower, but it exercises the real boot path (initramfs importing the pool).

Risk to design around: after a soft-reboot the system has never booted from its own disk. The installer
must verify the EFI entry, boot loader and initramfs before declaring success, or use kexec once as the
proof and soft-reboot only as the fast path.

**Account setup.** Omarchy already has this for pre-installed machines: `install/provisioning/setup-form.sh`
(keyboard, account, host name, time zone; `gum` prompts) and the `omarchy-provision-owner` first-boot
service. Reuse it rather than writing another.

**Encryption without an early question.** Create the pool encrypted with a temporary key, then in
account setup ask for the passphrase and run `zfs change-key`. Changing the wrapping key is instant and
does not rewrite data, so "choose only the disk" and "encrypted from the first byte" are compatible.

**Finalize.** Remove the temporary key, set the host name, enable the display manager, take the first
boot-environment snapshot ("factory"), which also gives Omarchy-style factory reset.

## Open questions

- Boot loader: GRUB (Debian default, limited ZFS feature support, needs a separate boot pool) or
  ZFSBootMenu (boot environments selectable at boot, the closest match to Omarchy's snapshot menu).
- Secure Boot with the out-of-tree ZFS module (MOK enrolment cannot be unattended).
- Dual boot: "choose only the disk" versus "use the free space"; Omarchy offers the latter.
- Hardware quirks: Omarchy's `install/hardware/*` fixes are per-vendor scripts; which run at image build
  time and which at first boot.
