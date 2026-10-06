# compat

Files Arch has and Debian does not, which Omarchy's scripts expect to find. Copied to `/` by `shims/install.sh`.
Each one exists so an upstream script runs unmodified; none of these files changes how Debian itself behaves.

| File | Why |
|---|---|
| `etc/pam.d/system-auth`, `system-login`, `system-local-login` | Arch's PAM stacks. Omarchy's lock screen service includes `system-local-login`; `increase-lockout-limit.sh` edits `system-auth`. Here they forward to Debian's `common-*`. |
| `usr/lib/systemd/system/linux-modules-cleanup.service` | Arch removes the running kernel's modules on upgrade and needs this unit to tidy up. Debian keeps old kernels installed, so the unit does nothing. |
| `etc/pacman.d/` | `post-install/pacman.sh` writes a mirror list here. Nothing reads it. |

Known difference: Arch's `system-auth` locks an account after failed logins (`pam_faillock`) and Omarchy raises the limit to 10.
Debian's login stack has no lockout, so there is nothing to raise. The lock screen has its own PAM file with the limit built in.

Two base-system differences are not files:

- **awk** is gawk on Arch and mawk on Debian. Installing `gawk` (`packages/extra.txt`) makes it the default through alternatives.
- **/bin/sh** is bash on Arch and dash on Debian, and trixie no longer offers a supported switch. kaiseki leaves the system
  shell alone; the rare bash-only snippet Omarchy runs through `sh -c` gets an overlay patch (`overlay/patches/`).

For the installer (root on ZFS):

| File | Why |
|---|---|
| `usr/lib/sysusers.d/kaiseki-wheel.conf` | Arch's `wheel` group. Upstream's first-boot setup adds the owner to it and grants it sudo. |
| `usr/share/keyrings/kaiseki-archive.gpg` | The public half of the key kaiseki's apt repository is signed with (docs/UPDATE.md). |
| `etc/apt/apt.conf.d/20kaiseki-periodic` | Refresh package lists daily; Omarchy's "update available" indicator reads them. |
| `etc/kernel/postinst.d/zz-kaiseki-vmlinuz-link` | Omarchy's update looks for the running kernel at Arch's path, `/usr/lib/modules/VERSION/vmlinuz`. Debian 14 has it there; on Debian 13 this leaves a link, and only when nothing is at that path. |
