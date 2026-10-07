# kaiseki

Omarchy's desktop on Debian, kept in step with upstream.

Kaiseki is the chef-composed set meal: the same "the chef decides" idea as omakase, served on Debian
instead of Arch. It does not fork Omarchy. It takes upstream as it is, supplies what Debian lacks, and
replaces only the Arch plumbing underneath.

Status (2026-10-06): **works in test VMs.** Omarchy v4.0.4 installs through its own packages and install
scripts and boots into the real desktop ([docs/PORT.md](docs/PORT.md)). An installer ISO puts it on an empty
disk in about a minute, on encrypted ZFS, without a reboot ([docs/INSTALLER.md](docs/INSTALLER.md)). Omarchy's
own update command works, with a ZFS snapshot first, from a signed apt repository
([docs/UPDATE.md](docs/UPDATE.md)). Nothing here has been installed on real hardware yet.

Project page: https://kaiseki.este.systems/ · package repository: https://kaiseki.este.systems/apt/

**Base:** Debian testing. It already has what Omarchy needs (Hyprland 0.56, Qt 6.11, Quickshell 0.3.1,
kernel 7.2), so nothing is rebuilt and a full test run takes 16 minutes. Debian 13 also works for the desktop
but needs six packages rebuilt from unstable and a backports selection, and takes 31 minutes; that gap grows
with every Omarchy release. The installer and the repository are built for testing only.

![desktop](docs/img/desktop.png)

## How it works

| Layer | What | Where |
|---|---|---|
| Upstream | Omarchy at a pinned tag (`UPSTREAM`) and its package recipes at a pinned commit (`UPSTREAM_PKGS`), cloned read-only | `.cache/` via `bin/kaiseki fetch` |
| Package map | Every upstream package has a decision: a Debian package, a recipe, or a reasoned "not on Debian" | `map/arch-to-debian.tsv`, checked by `bin/kaiseki survey` |
| Recipes | Arch recipes (Omarchy's, Arch's own, one of kaiseki's) run with Debian's `makepkg` and wrapped as `.deb`: 24 packages | `packages/pkgbuild2deb`, `packages/recipes.txt`, `map/build-tools.tsv` |
| Shims | Stand-ins for `pacman`, `yay`, `checkupdates`, `snapper`, `cryptsetup` and the boot stack, so upstream scripts run unmodified | `shims/` |
| Compat | The few files and packages Arch has and Debian lacks | `compat/`, `packages/extra.txt` |
| Overlay | Patches only where nothing else reaches (three), files that must stay Debian's, files left out | `overlay/` |
| Repository | The built packages as a signed apt repository; what installed machines update from | `packages/publish`, `packages/repo.conf` |
| Installer | Prepared root as a ZFS stream, live ISO, one-question install, upstream's first-boot setup | `installer/`, `tests/run-installer` |
| Tests | Fresh VM per run: install, reboot, checks; the installer and an update driven end to end | `tests/`, `vm/vm` |
| Web | The project page and the repository's page | `site/` |
| Debian 13 only | Six source packages rebuilt from unstable, backports selection | `packages/build.sh`, `packages/rebuild.txt`, `packages/backports-pins` |

Principles: shims before patches (upstream changes pass through); stage a new upstream release next to
the current one and switch only when the checks pass; Debian keeps its own kernel, boot loader and
package manager.

## Findings (Omarchy v4.0.4)

- 204 upstream packages. On Debian testing 142 map to Debian packages, 24 are built from recipes, 36 are
  Arch-only or hardware-specific, and 2 are missing: `pinta` and `dotnet-runtime` need the .NET SDK.
- All 49 of Omarchy's system setup scripts, its per-user setup, its first-boot owner setup and its update
  command run unmodified.
- Three overlay patches in total: a QML reserved word (Debian 13's Qt 6.8 only), a bash-only `echo -e` run
  through `/bin/sh`, and a minimum password length, because ZFS refuses passphrases under 8 characters.
- Things Arch bundles and Debian splits were the recurring kind of gap, each found by a test or a person:
  QML modules, `gtk-launch`, `pactl`, `xkbcli`, gawk. `tests/audit-commands` now looks for them.

## Commands

On the host:

```
bin/kaiseki fetch [TAG]                # upstream at a tag, and its recipes
bin/kaiseki survey                     # package decisions vs real Debian suites -> docs/SURVEY.md
KAISEKI_BASE=forky tests/run NAME      # fresh Debian testing VM: install everything, reboot, check, screenshot
packages/publish NAME                  # sign and publish that VM's packages as the apt repository
tests/run-installer NAME               # empty VM: the installer ISO end to end, including a cold boot
tests/run-update NAME                  # on that machine: Omarchy's own update, checked
installer/try NAME                     # try the installer by hand in a new VM
site/deploy                            # the project page
vm/vm up|metal|ssh|push|shot|key|type|view|down|destroy|list [NAME]
```

Inside a Debian build machine (the test VM today):

```
packages/pkgbuild2deb NAME...          # recipe -> .deb in /srv/kaiseki/repo
shims/install.sh                       # the stand-ins and compat files
tests/install.sh                       # the whole port, start to finish
tests/check.sh                         # after the reboot: is this really Omarchy's session?
tests/audit-commands                   # programs Omarchy calls that this system lacks
installer/build-root.sh                # the prepared system as a ZFS stream (from the published repository)
installer/build-iso.sh                 # the installer ISO
```

Not affiliated with Omarchy or 37signals. Omarchy is MIT licensed; so is this.
