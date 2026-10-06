#!/bin/bash
# tests/install.sh   (inside a fresh Debian 13 test VM, as the cloud-init user; tests/run puts the inputs in place)
# The whole port, start to finish, the way a kaiseki installer will do it. Inputs in $HOME:
#   kaiseki/       this repository        omarchy-src/   upstream at the pinned tag
#   omarchy-pkgs/  upstream's recipes
# Every stage prints one line; the first failure stops the run.
set -euo pipefail
K=$HOME/kaiseki; export OMARCHY_SRC=$HOME/omarchy-src PKGS=$HOME/omarchy-pkgs
list() { grep -v '^#' "$1" | grep -v '^$'; }
stage() { echo; echo "### $* ($(date +%T))"; }

stage "apt sources: backports, and unstable as a source of source packages only"
printf 'deb http://deb.debian.org/debian trixie-backports main\ndeb-src http://deb.debian.org/debian unstable main\n' | sudo tee /etc/apt/sources.list.d/kaiseki.list >/dev/null
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq build-essential devscripts dpkg-dev >/dev/null

stage "rebuild what Debian 13 has too old: $(list "$K/packages/rebuild.txt" | tr '\n' ' ')"
sh "$K/packages/build.sh" $(list "$K/packages/rebuild.txt")

stage "shims and compat files"
sudo sh "$K/shims/install.sh"

stage "overlay patches onto upstream"
for p in "$K"/overlay/patches/*.patch; do (cd "$OMARCHY_SRC" && patch -p1 --no-backup-if-mismatch < "$p" >/dev/null) && echo "   applied $(basename "$p")"; done

stage "upstream recipes -> Debian packages: $(list "$K/packages/recipes.txt" | tr '\n' ' ')"
bash "$K/packages/pkgbuild2deb" $(list "$K/packages/recipes.txt") 2>&1 | grep -v 'dpkg-deb: warning'

stage "upstream's package list, through the pacman shim"
sudo pacman -S --noconfirm --needed $(list "$OMARCHY_SRC/install/omarchy-base.packages") omarchy > "$HOME/packages.log" 2>&1 || { tail -20 "$HOME/packages.log"; exit 1; }
echo "   $(dpkg -l | grep -c '^ii') Debian packages installed; not available yet: $(grep -c UNAVAILABLE /var/log/kaiseki/pacman.log || true)"

stage "stay reachable (test VMs only)"
sudo bash "$K/tests/keep-reachable.sh"

stage "upstream system setup: omarchy-apply-system"
sudo env OMARCHY_PATH=/usr/share/omarchy PATH="/usr/share/omarchy/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" OMARCHY_LOG_TO_STDOUT=1 \
    omarchy-apply-system --install-user "$USER" --first-install > "$HOME/apply-system.log" 2>&1 || { grep -E 'Failed|rror' "$HOME/apply-system.log" | tail -5; exit 1; }
echo "   $(grep -c '^Starting' "$HOME/apply-system.log" || true) scripts ran"

stage "user: home from /etc/skel, autologin, upstream's omarchy-provision-user"
# the installer will create the owner after the packages, so /etc/skel seeds the home; cloud-init made this one before
cp -aT /etc/skel "$HOME"
printf '[Autologin]\nUser=%s\nSession=omarchy.desktop\n' "$USER" | sudo tee /etc/sddm.conf.d/autologin.conf >/dev/null
bash -lc 'OMARCHY_SETUP_CONTEXT=provision-owner OMARCHY_LOG_TO_STDOUT=1 omarchy-provision-user --first-install' > "$HOME/provision-user.log" 2>&1 < /dev/null || { tail -8 "$HOME/provision-user.log"; exit 1; }
tail -1 "$HOME/provision-user.log"

stage "done: reboot into the session"
