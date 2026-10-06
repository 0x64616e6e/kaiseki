# kaiseki

Omarchy's desktop on Debian, kept in step with upstream.

Kaiseki is the chef-composed set meal: the same "the chef decides" idea as omakase, served on Debian
instead of Arch. It does not fork Omarchy. It takes upstream as it is, supplies what Debian lacks, and
replaces only the Arch plumbing underneath.

Status: **feasibility trial** (2026-10-06). Nothing here is installed on a real system yet; every step is
exercised in a throwaway Debian 13 VM.

## How it works

| Layer | What | Where |
|---|---|---|
| Upstream | Omarchy at a pinned tag (`UPSTREAM`), cloned read-only | `.cache/omarchy` via `bin/kaiseki fetch` |
| Package map | Every upstream package has a decision: a Debian package, "build", or "skip" | `map/arch-to-debian.tsv`, checked by `bin/kaiseki survey` → `docs/SURVEY.md` |
| Package layer | What Debian 13 lacks or has too old, rebuilt from Debian unstable into a local apt repo | `packages/build.sh` |
| Shims | Stand-ins for `pacman`, `yay` and the boot stack, so upstream scripts run unmodified | `shims/` (to do) |
| Overlay | Patches only where a shim cannot reach | `overlay/` (to do) |
| Tests | Fresh VM per run: install, start the session, check, screenshot | `vm/vm`, `tests/` |

Principles: shims before patches (upstream changes pass through); stage a new upstream release next to
the current one and switch only when the checks pass; Debian keeps its own kernel, boot loader and
package manager.

## Findings so far (Omarchy v4.0.4 on Debian 13)

- 204 upstream packages: 134 are in Debian 13, 7 in trixie-backports (including Quickshell 0.3.0),
  1 only in unstable, 26 need building or a vendor installer, 36 are Arch-only or hardware-specific.
- The shell (102 QML files) imports only Quickshell modules that the Debian package provides.
- The blocker is Hyprland: upstream needs 0.56 (Lua configuration), backports has 0.55. Its unstable
  source package needs three things Debian 13 lacks: libinput >= 1.29, lua5.5, wayland-protocols >= 1.49.

## Commands

```
bin/kaiseki fetch [TAG]        # upstream at a tag
bin/kaiseki survey             # package decisions vs real Debian suites -> docs/SURVEY.md
vm/vm up NAME                  # fresh Debian 13 test machine (KVM, virtual GPU, ssh)
vm/vm ssh NAME [CMD]           # run in it;  vm/vm shot NAME out.png  takes a screenshot
vm/vm destroy NAME
packages/build.sh SRC...       # inside a Debian 13 machine: rebuild unstable sources into /srv/kaiseki/repo
```

Not affiliated with Omarchy or 37signals. Omarchy is MIT licensed; so is this.
