#!/bin/sh
# Install the shims, their data and the compat files on a Debian machine (run as root, from the kaiseki tree).
# /usr/local/bin is ahead of /usr/bin in both the user PATH and sudo's secure_path.
set -eu
T=$(cd "$(dirname "$0")/.." && pwd)
install -d /usr/share/kaiseki /var/log/kaiseki
chmod 1777 /var/log/kaiseki
install -m 644 "$T/map/arch-to-debian.tsv" /usr/share/kaiseki/arch-to-debian.tsv
install -m 755 "$T/shims/pacman" /usr/local/bin/pacman
ln -sf pacman /usr/local/bin/yay
for n in mkinitcpio limine-update limine-mkinitcpio limine-snapper-sync limine-entry-tool snapper; do install -m 755 "$T/shims/noop" "/usr/local/bin/$n"; done
(cd "$T/compat" && find etc usr -type f ! -name .keep ! -name README.md -exec install -D -m 644 -o root -g root {} /{} \;)
install -d /etc/pacman.d
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $(grep -v '^#' "$T/packages/extra.txt") >/dev/null
echo "kaiseki shims and compat files installed"
