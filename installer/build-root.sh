#!/bin/bash
# installer/build-root.sh   (on a Debian 13 build machine that has /srv/kaiseki/repo; user with sudo)
# Build the prepared root file system the installer lays down with `zfs receive`:
# Debian 13 + kernel + ZFS + firmware + Omarchy's whole package set, nothing machine-specific.
# Machine-specific work (hardware fixes, host id, initramfs, boot loader, the owner) happens at install time.
# Output: /srv/kaiseki/image/root.zfs.zst and manifest.
set -euo pipefail
K=$(cd "$(dirname "$0")/.." && pwd); OMARCHY_SRC=${OMARCHY_SRC:-$HOME/omarchy-src}
REPO=/srv/kaiseki/repo; OUT=/srv/kaiseki/image; POOL=kbuild; IMG=/var/tmp/kbuild.img; R=/mnt/kbuild
MIRROR=http://deb.debian.org/debian
list() { grep -v '^#' "$1" | grep -v '^$'; }
stage() { echo; echo "### $* ($(date +%T))"; }
in_root() { sudo chroot "$R" /usr/bin/env -i HOME=/root TERM=linux LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin "$@"; }
cleanup() {
    for m in dev proc sys run; do sudo umount -R "$R/$m" 2>/dev/null || sudo umount -Rl "$R/$m" 2>/dev/null || true; done
    sudo zpool export "$POOL" 2>/dev/null || true
}
trap cleanup EXIT

stage "empty pool in a file"
sudo zpool export "$POOL" 2>/dev/null || true; sudo rm -f "$IMG"; sudo truncate -s 30G "$IMG"; sudo mkdir -p "$R" "$OUT"
sudo zpool create -f -o ashift=12 -O compression=zstd -O acltype=posixacl -O xattr=sa -O relatime=on -O normalization=formD \
    -O mountpoint=none -R "$R" "$POOL" "$IMG"
sudo zfs create -o mountpoint=/ -o canmount=noauto "$POOL/root"; sudo zfs mount "$POOL/root"

stage "Debian 13 base, kernel, ZFS, firmware"
# all three suites from the start: the kernel must be the current one, the same the live ISO gets
sudo mmdebstrap --variant=important --components=main,contrib,non-free-firmware \
    --include="$(list "$K/installer/base-packages.txt" | tr '\n' ',' | sed 's/,$//')" \
    trixie "$R" "deb $MIRROR trixie main contrib non-free-firmware" "deb $MIRROR trixie-updates main contrib non-free-firmware" \
    "deb http://security.debian.org/debian-security trixie-security main contrib non-free-firmware" > "$HOME/build-root.bootstrap.log" 2>&1 || { tail -20 "$HOME/build-root.bootstrap.log"; exit 1; }
for m in proc sys dev dev/pts run; do sudo mount --rbind "/$m" "$R/$m" 2>/dev/null || sudo mount --bind "/$m" "$R/$m"; sudo mount --make-rslave "$R/$m"; done
kver=$(ls "$R/lib/modules" | sort -V | tail -1)
[ -n "$(find "$R/lib/modules/$kver" -name 'zfs.ko*' | head -1)" ] || { echo "no ZFS module was built for $kver"; exit 1; }
echo "   kernel $kver with ZFS module"

stage "apt sources, local repository, no services started in the chroot"
printf '#!/bin/sh\nexit 101\n' | sudo tee "$R/usr/sbin/policy-rc.d" >/dev/null; sudo chmod 755 "$R/usr/sbin/policy-rc.d"
sudo rm -f "$R/etc/resolv.conf"; sudo cp /etc/resolv.conf "$R/etc/resolv.conf"
sudo tee "$R/etc/apt/sources.list" >/dev/null <<S
deb $MIRROR trixie main contrib non-free-firmware
deb $MIRROR trixie-updates main contrib non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free-firmware
deb $MIRROR trixie-backports main contrib non-free-firmware
S
sudo mkdir -p "$R$REPO"; sudo cp "$REPO"/*.deb "$R$REPO/"; sudo rm -f "$R$REPO"/*-dbgsym_*.deb
in_root sh -c "cd $REPO && apt-get install -y -qq dpkg-dev >/dev/null && dpkg-scanpackages -m . /dev/null 2>/dev/null > Packages && gzip -kf Packages"
echo "deb [trusted=yes] file:$REPO ./" | sudo tee "$R/etc/apt/sources.list.d/kaiseki-local.list" >/dev/null
printf 'Package: *\nPin: origin ""\nPin-Priority: 995\n' | sudo tee "$R/etc/apt/preferences.d/kaiseki" >/dev/null
in_root apt-get update -qq
echo 'en_US.UTF-8 UTF-8' | sudo tee "$R/etc/locale.gen" >/dev/null; in_root locale-gen >/dev/null
echo 'LANG=en_US.UTF-8' | sudo tee "$R/etc/default/locale" >/dev/null

stage "kaiseki shims and compat files"
sudo mkdir -p "$R/usr/share/kaiseki/tree"; sudo tar -C "$K" -c bin compat installer map overlay packages shims UPSTREAM UPSTREAM_PKGS | sudo tar -x -C "$R/usr/share/kaiseki/tree" --no-same-owner
in_root sh /usr/share/kaiseki/tree/shims/install.sh

stage "upstream's package list, through the pacman shim"
in_root pacman -S --noconfirm --needed $(list "$OMARCHY_SRC/install/omarchy-base.packages") omarchy > "$HOME/build-root.packages.log" 2>&1 || { tail -20 "$HOME/build-root.packages.log"; exit 1; }
echo "   $(in_root dpkg -l | grep -c '^ii') Debian packages; not available yet: $(grep -c UNAVAILABLE "$R/var/log/kaiseki/pacman.log" || true)"
in_root dpkg -l omarchy omarchy-settings hyprland quickshell | awk '/^ii/ {print "   " $2, $3}'

stage "make it nobody's machine"
in_root apt-get clean
sudo rm -f "$R/usr/sbin/policy-rc.d" "$R"/etc/ssh/ssh_host_* "$R/etc/hostid" "$R/var/lib/dbus/machine-id" "$R/var/log/kaiseki/pacman.log.old"
sudo truncate -s 0 "$R/etc/machine-id"
sudo rm -f "$R/etc/resolv.conf"; sudo ln -s ../run/systemd/resolve/stub-resolv.conf "$R/etc/resolv.conf"
echo kaiseki | sudo tee "$R/etc/hostname" >/dev/null
sudo find "$R/var/log" -type f \( -name '*.log' -o -name '*.gz' \) ! -path '*/kaiseki/*' -delete; sudo rm -rf "$R"/tmp/* "$R"/var/tmp/*

stage "export as a ZFS stream"
for m in dev proc sys run; do sudo umount -R "$R/$m" 2>/dev/null || sudo umount -Rl "$R/$m" 2>/dev/null || true; done
tag=$(cat "$K/UPSTREAM"); snap="$POOL/root@$tag"
sudo zfs snapshot "$snap"
used=$(sudo zfs get -Hp -o value referenced "$snap"); logical=$(sudo zfs get -Hp -o value logicalreferenced "$snap")
sudo sh -c "zfs send '$snap' | zstd -T0 -9 -q > '$OUT/root.zfs.zst.tmp'" && sudo mv "$OUT/root.zfs.zst.tmp" "$OUT/root.zfs.zst"
sudo tee "$OUT/manifest" >/dev/null <<M
upstream=$tag
built=$(date -u +%Y-%m-%dT%H:%MZ)
kernel=$kver
zfs=$(in_root dpkg-query -W -f='${Version}' zfsutils-linux 2>/dev/null || true)
installed_bytes=$logical
stream_bytes=$(stat -c %s "$OUT/root.zfs.zst")
sha256=$(sha256sum "$OUT/root.zfs.zst" | cut -d' ' -f1)
M
cat "$OUT/manifest" | sed 's/^/   /'
stage "done"
