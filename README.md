# kaiseki

Omarchy's desktop on Debian, kept in step with upstream.

Kaiseki is the chef-composed set meal: the same "the chef decides" idea as omakase, served on Debian
instead of Arch. It does not fork Omarchy. It takes upstream as it is, supplies what Debian lacks, and
replaces only the Arch plumbing underneath.

Status (2026-10-06): **works in test VMs.** Omarchy v4.0.4 installs through its own packages and install
scripts and boots into the real desktop ([docs/PORT.md](docs/PORT.md)), and an installer ISO puts it on an
empty disk in about a minute, on encrypted ZFS, without a reboot ([docs/INSTALLER.md](docs/INSTALLER.md)).
Nothing here has been installed on real hardware yet.

**Base:** Debian testing. It already has what Omarchy needs (Hyprland 0.56, Qt 6.11, Quickshell 0.3.1,
kernel 7.2), so nothing is rebuilt and a full test run takes 16 minutes. Debian 13 also works but needs six
packages rebuilt from unstable, two patches and a backports selection, and takes 31 minutes; that gap grows
with every Omarchy release.

![desktop](docs/img/desktop.png)

## How it works

| Layer | What | Where |
|---|---|---|
| Upstream | Omarchy at a pinned tag (`UPSTREAM`) and its package recipes at a pinned commit (`UPSTREAM_PKGS`), cloned read-only | `.cache/` via `bin/kaiseki fetch` |
| Package map | Every upstream package has a decision: a Debian package, "build", or "skip" | `map/arch-to-debian.tsv`, checked by `bin/kaiseki survey` → `docs/SURVEY.md` |
| Rebuilds | What Debian 13 has too old, rebuilt from Debian unstable into a local apt repo | `packages/build.sh`, `packages/rebuild.txt` |
| Recipes | Upstream's own Arch recipes run with Debian's `makepkg` and wrapped as `.deb` | `packages/pkgbuild2deb`, `packages/recipes.txt` |
| Shims | Stand-ins for `pacman`, `yay` and the boot stack, so upstream scripts run unmodified | `shims/` |
| Compat | The few files Arch has and Debian lacks | `compat/`, `packages/extra.txt` |
| Overlay | Patches only where nothing else reaches (two so far), and files that must stay Debian's | `overlay/` |
| Installer | Prepared root as a ZFS stream, live ISO, one-question install, upstream's first-boot setup | `installer/`, `tests/run-installer` |
| Tests | Fresh VM per run: the whole install, reboot, checks, screenshot | `tests/run`, `vm/vm` |

Principles: shims before patches (upstream changes pass through); stage a new upstream release next to
the current one and switch only when the checks pass; Debian keeps its own kernel, boot loader and
package manager.

## Findings so far (Omarchy v4.0.4 on Debian 13)

- 204 upstream packages: 134 are in Debian 13, 7 in trixie-backports (including Quickshell 0.3.0),
  1 only in unstable, 26 need building (5 done, from upstream recipes), 36 are Arch-only or hardware-specific.
- The shell (102 QML files) imports only Quickshell modules that the Debian package provides.
- The blocker is Hyprland: upstream needs 0.56 (Lua configuration), backports has 0.55. Its unstable
  source package needs three things Debian 13 lacks: libinput >= 1.29, lua5.5, wayland-protocols >= 1.49.

## Commands

```
bin/kaiseki fetch [TAG]        # upstream at a tag, and its recipes
bin/kaiseki survey             # package decisions vs real Debian suites -> docs/SURVEY.md
tests/run NAME                 # fresh VM: install everything, reboot, check, screenshot (KAISEKI_BASE=forky for testing)
tests/run-installer NAME       # empty VM: the installer ISO end to end, including a cold boot
vm/vm up|ssh|push|shot|key|type|down|destroy|list [NAME]
```

Inside a Debian 13 machine (the test VM today):

```
packages/build.sh SRC...       # rebuild unstable source packages into /srv/kaiseki/repo
packages/pkgbuild2deb NAME...  # upstream recipe -> .deb in the same repo
shims/install.sh               # pacman/yay shims, compat files
tests/install.sh               # the whole port, start to finish
tests/check.sh                 # after the reboot: is this really Omarchy's session?
```

Not affiliated with Omarchy or 37signals. Omarchy is MIT licensed; so is this.
