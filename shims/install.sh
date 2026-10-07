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
for n in mkinitcpio limine-mkinitcpio limine-snapper-sync limine-entry-tool pacman-key; do install -m 755 "$T/shims/noop" "/usr/local/bin/$n"; done
for n in limine-update checkupdates snapper limine-snapper-restore; do install -m 755 "$T/shims/$n" "/usr/local/bin/$n"; done
printf '#!/bin/sh\n# kaiseki shim for paccache: apt keeps no old package versions worth pruning; empty its cache instead.\nexec apt-get clean\n' > /usr/local/bin/paccache; chmod 755 /usr/local/bin/paccache
install -m 755 "$T/shims/cryptsetup" /usr/local/sbin/cryptsetup   # sbin: ahead of /usr/sbin for root and services
install -m 755 "$T/shims/kaiseki-zfs-guard" /usr/local/sbin/kaiseki-zfs-guard
install -m 755 "$T/shims/kaiseki-initramfs" /usr/local/sbin/kaiseki-initramfs
(cd "$T/compat" && find etc usr -type f ! -name .keep ! -name README.md -exec install -D -m 644 -o root -g root {} /{} \;)
chmod 755 /etc/kernel/postinst.d/zz-kaiseki-vmlinuz-link /etc/kernel/postinst.d/zzz-kaiseki-zfs-module-check /etc/initramfs/post-update.d/zz-kaiseki-fingerprint
for k in /usr/lib/modules/*; do [ -d "$k" ] && /etc/kernel/postinst.d/zz-kaiseki-vmlinuz-link "$(basename "$k")"; done
getent group wheel >/dev/null || groupadd -r wheel
# Omarchy's scripts run "sudo pacman ..."; the shims live in /usr/local, which newer Debian drops from sudo's path
printf 'Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"\n' > /etc/sudoers.d/kaiseki-path
chmod 440 /etc/sudoers.d/kaiseki-path
install -d /etc/pacman.d
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $(grep -v '^#' "$T/packages/extra.txt") >/dev/null
echo "kaiseki shims and compat files installed"
