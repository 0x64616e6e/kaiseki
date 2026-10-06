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

## From a build to the machine: the repository

kaiseki's own packages (Omarchy itself and everything built from recipes) are published as an ordinary signed
Debian repository. The installer image is built from it and installed machines update from it:

```
deb [signed-by=/usr/share/keyrings/kaiseki-archive.gpg] https://files.este.systems/kaiseki forky main
```

`packages/publish BUILD_VM` on the host:

1. copies the `.deb` files out of the build VM;
2. lays them out as `pool/<release>/` and `dists/<release>/main/binary-amd64/`, and writes `Release`;
3. signs it (`InRelease`, `Release.gpg`) with the kaiseki archive key;
4. writes the repository's web page from the index it has just signed (`site/repo.html` is the template);
5. uploads packages first and the signed index last, then removes superseded packages.

Settings are in `packages/repo.conf`. The server side is plain files behind nginx: `installer/nginx-kaiseki-repo.conf`.

**The archive key** lives on the publishing machine only (`~/.local/share/kaiseki/gnupg`), never in a VM and
never on the server. Its public half is `compat/usr/share/keyrings/kaiseki-archive.gpg`, which every installed
machine carries. Whoever holds the private key can sign packages that machines will install: back it up, keep
it private. Fingerprint `23DC F429 17B5 FA71 C4B0 1AE0 946D 46A4 FB8D BC33`.

A new upstream release reaches machines like this: `bin/kaiseki fetch TAG`, rebuild the recipes
(`packages/pkgbuild2deb`), run the tests, `packages/publish`. Machines then see a newer `omarchy` package and
Omarchy's indicator offers the update. Rebuilding the installer image is only needed for new installs.

## Verified, and not

2026-10-06, `tests/run-update` on a machine made by the installer, with the newer package in a local repository:

- nothing to update at first; after a newer `omarchy` package appears, Omarchy reports `4.0.4-1 -> 4.0.4-1.1`;
- `omarchy-update -y` exits 0; a ZFS snapshot exists and does not contain the new package's files;
- the package is upgraded, nothing is left pending, the session survives; the machine reboots cleanly afterwards.

Also verified: `apt` on Debian testing accepts the published repository and its signature, and the image
build installs kaiseki's packages from it.

Not verified yet:

- the full installer and update run on an image built from the published repository (in progress when this
  was written);
- an update that brings a new kernel (ZFS module rebuild, the copies on the EFI partition);
- a real new Omarchy release going through fetch, rebuild, publish and update;
- rolling back to an update snapshot from ZFSBootMenu.
