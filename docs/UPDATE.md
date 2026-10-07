# Updating

Two halves: how an installed machine updates, and how a new build reaches it.

## On the machine: Omarchy's own update

`omarchy-update` (and the "Update System" entry in the bar and the menu) runs unmodified. Each step it calls is
answered by a stand-in that does the Debian or ZFS equivalent:

| Omarchy's step | What it calls | On kaiseki |
|---|---|---|
| Is there an update? | `checkupdates`, `pacman -Q omarchy` | `shims/checkupdates` lists apt's pending upgrades; the pacman shim reports the real package version |
| Snapshot first | `snapper create`, `snapper cleanup` | `shims/snapper`: `zfs snapshot rpool/ROOT/kaiseki@update-<time>`, newest five kept |
| Signing keys | `pacman-key`, `archlinux-keyring` | nothing to do: apt verifies against the archive keys already installed |
| System packages | `pacman -Syu` | `apt-get update` and `apt-get dist-upgrade`, local config files kept |
| Migrations | `omarchy-migrate` | upstream's own, run as they are |
| AUR, orphans | `yay -Sua`, `pacman -Qtdq` | none: everything comes from apt |
| Prune the cache | `paccache` | `apt-get clean` |
| Restart or reboot? | looks for the running kernel under `/usr/lib/modules` | Debian 14 keeps the kernel there too; on Debian 13 a link is left at that path |
| Roll back | `limine-snapper-restore` | `shims/limine-snapper-restore` explains the way through ZFSBootMenu, which lists the snapshots at boot |

Debian's own packages come from Debian's mirrors. Package lists are refreshed daily
(`compat/etc/apt/apt.conf.d/20kaiseki-periodic`), which is what the "update available" indicator reads.

## Kernels and ZFS

The root file system is on ZFS, which DKMS builds for each kernel, and every ZFS release supports kernels only up
to a stated version (`Linux-Maximum` in its `META` file). On a fast-moving base a kernel can arrive before ZFS
supports it; booting it would mean an initramfs that cannot open the pool. `shims/kaiseki-zfs-guard` covers this
three ways:

| When | What |
|---|---|
| Before `omarchy-update` upgrades the system | If the pending kernel is newer than the pending ZFS supports, the kernel metapackages are held and everything else updates. The hold is released by itself once ZFS has caught up. |
| Any `apt` transaction (`DPkg::Pre-Install-Pkgs`) | A transaction that would install an unsupported kernel is refused, with the reason, before anything changes. |
| After a kernel is installed (`/etc/kernel/postinst.d`) | Every installed kernel must have a ZFS module. If one has not, it is reported and the boot loader's default is pinned to the newest kernel that has; the pin is released when all have. |

## From a build to the machine: the repository

kaiseki's own packages (Omarchy itself and everything built from recipes) are published as an ordinary signed
Debian repository. The installer image is built from it and installed machines update from it:

```
deb [signed-by=/usr/share/keyrings/kaiseki-archive.gpg] https://kaiseki.este.systems/apt forky main
```

`packages/publish BUILD_VM` on the host:

1. copies the `.deb` files out of the build VM;
2. lays them out as `pool/<release>/` and `dists/<release>/main/binary-amd64/`, and writes `Release`;
3. signs it (`InRelease`, `Release.gpg`) with the kaiseki archive key;
4. writes the repository's web page from the index it has just signed (the template is `repo.html` in the
   separate site repository, `KAISEKI_REPO_PAGE`; without it a plain page is written);
5. uploads packages first and the signed index last, then removes superseded packages.

Settings are in `packages/repo.conf`. The server side is plain files behind nginx; the project page and the
server's configuration are kept in a separate repository.

**The archive key** lives on the publishing machine only (`~/.local/share/kaiseki/gnupg`), never in a VM and
never on the server. Its public half is `compat/usr/share/keyrings/kaiseki-archive.gpg`, which every installed
machine carries. Whoever holds the private key can sign packages that machines will install: back it up, keep
it private. Fingerprint `23DC F429 17B5 FA71 C4B0 1AE0 946D 46A4 FB8D BC33`.

A new upstream release reaches machines like this: `bin/kaiseki fetch TAG`, rebuild the recipes
(`packages/pkgbuild2deb`), run the tests, `packages/publish`. Machines then see a newer `omarchy` package and
Omarchy's indicator offers the update. Rebuilding the installer image is only needed for new installs.

## Verified, and not

2026-10-07, `tests/run-installer` then `tests/run-update`, on a machine installed from an image that was itself
built from the published repository:

- the machine's `omarchy` package comes from `https://kaiseki.este.systems/apt` (first published at `files.este.systems/kaiseki`, which now redirects); no repository copy is on its disk;
- nothing to update at first; after a newer `omarchy` package appears (in a second, local repository the test
  adds for the purpose), Omarchy reports `4.0.4-1 -> 4.0.4-1.1`;
- `omarchy-update -y` exits 0 without stopping at a prompt; a ZFS snapshot exists and does not contain the new
  package's files;
- the package is upgraded, nothing is left pending, the session survives.

- `tests/zfs-guard.sh`, 12 checks: the supported range is read correctly; apt refuses a dummy package named like a
  too-new kernel and installs an ordinary one; with the maximum lowered for the test the kernel is held before an
  upgrade and released after; a kernel faked without a ZFS module is reported and the boot default pinned, then
  released. Run by `tests/run-update` on a machine installed from the ISO.

Not verified yet:

- a real kernel that ZFS does not support, and an update that brings a new supported kernel (ZFS module rebuild, the copies on the EFI partition);
- a real new Omarchy release going through fetch, rebuild, publish and update;
- rolling back to an update snapshot from ZFSBootMenu.
