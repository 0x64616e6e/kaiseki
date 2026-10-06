#!/bin/sh
# Install the shims and their data on a Debian machine (run as root, from the kaiseki tree).
# /usr/local/bin is ahead of /usr/bin in both the user PATH and sudo's secure_path.
set -eu
T=$(cd "$(dirname "$0")/.." && pwd)
install -d /usr/share/kaiseki/vendor /var/log/kaiseki /var/lib/kaiseki/vendor
chmod 1777 /var/log/kaiseki
install -m 644 "$T/map/arch-to-debian.tsv" /usr/share/kaiseki/arch-to-debian.tsv
for f in "$T"/packages/vendor/*.sh; do [ -f "$f" ] && install -m 755 "$f" /usr/share/kaiseki/vendor/; done
install -m 755 "$T/shims/pacman" /usr/local/bin/pacman
ln -sf pacman /usr/local/bin/yay
for n in mkinitcpio limine-update limine-mkinitcpio limine-snapper-sync limine-entry-tool snapper; do install -m 755 "$T/shims/noop" "/usr/local/bin/$n"; done
echo "kaiseki shims installed"
