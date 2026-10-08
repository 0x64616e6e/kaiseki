#!/bin/bash
# installer/build-root.sh   (on a Debian build machine, after packages/publish; user with sudo)
# Build the prepared root file system the installer lays down with `zfs receive`:
# Debian (the build machine's release) + kernel + ZFS + firmware + Omarchy's whole package set, nothing machine-specific.
# Machine-specific work (hardware fixes, host id, initramfs, boot loader, the owner) happens at install time.
# Output: /srv/kaiseki/image/root.zfs.zst and manifest.
set -euo pipefail
# Everything below mounts things, so it runs in a mount namespace of its own. Otherwise any service on the build
# machine that (re)starts during the build keeps a private copy of the build mounts and the pool can never be
# exported: "pool is busy" on the next run.
if [ -z "${KAISEKI_NS:-}" ]; then exec sudo unshare -m --propagation private sudo -u "$(id -un)" env KAISEKI_NS=1 HOME="$HOME" OMARCHY_SRC="${OMARCHY_SRC:-}" bash "$0" "$@"; fi
[ -n "${OMARCHY_SRC:-}" ] || unset OMARCHY_SRC
K=$(cd "$(dirname "$0")/.." && pwd); OMARCHY_SRC=${OMARCHY_SRC:-$HOME/omarchy-src}
REPO=/srv/kaiseki/repo; OUT=/srv/kaiseki/image; POOL=kbuild; IMG=/var/tmp/kbuild.img; R=/mnt/kbuild
MIRROR=http://deb.debian.org/debian
SUITE=$(. /etc/os-release; echo "$VERSION_CODENAME")   # the image is the same Debian release as the build machine
SEC="deb http://security.debian.org/debian-security $SUITE-security main contrib non-free-firmware"
list() { grep -v '^#' "$1" | grep -v '^$'; }
stage() { echo; echo "### $* ($(date +%T))"; }
in_root() { sudo chroot "$R" /usr/bin/env -i HOME=/root TERM=linux LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin "$@"; }
cleanup() {
    # daemons that package scripts started inside the chroot (gpg-agent, dirmngr ...) keep the pool busy
    for d in /proc/[0-9]*; do [ "$(sudo readlink "$d/root" 2>/dev/null)" = "$R" ] && sudo kill -9 "${d#/proc/}" 2>/dev/null; done   # still running inside the chroot
    for m in dev proc sys run; do sudo umount -R "$R/$m" 2>/dev/null || sudo umount -Rl "$R/$m" 2>/dev/null || true; done
    sudo zpool export "$POOL" 2>/dev/null || true
}
trap cleanup EXIT

stage "empty pool in a file"
sudo zpool export "$POOL" 2>/dev/null || true; sudo rm -f "$IMG"; sudo truncate -s 30G "$IMG"; sudo mkdir -p "$R" "$OUT"
sudo zpool create -f -o ashift=12 -O compression=zstd -O acltype=posixacl -O xattr=sa -O relatime=on -O normalization=formD \
    -O mountpoint=none -R "$R" "$POOL" "$IMG"
sudo zfs create -o mountpoint=/ -o canmount=noauto "$POOL/root"; sudo zfs mount "$POOL/root"

stage "Debian $SUITE base, kernel, ZFS, firmware"
# all three suites from the start: the kernel must be the current one, the same the live ISO gets
sudo mmdebstrap --variant=important --components=main,contrib,non-free-firmware \
    --include="$(list "$K/installer/base-packages.txt" | tr '\n' ',' | sed 's/,$//')" \
    "$SUITE" "$R" "deb $MIRROR $SUITE main contrib non-free-firmware" "deb $MIRROR $SUITE-updates main contrib non-free-firmware" \
    "$SEC" > "$HOME/build-root.bootstrap.log" 2>&1 || { tail -20 "$HOME/build-root.bootstrap.log"; exit 1; }
for m in proc sys dev dev/pts run; do sudo mount --rbind "/$m" "$R/$m" 2>/dev/null || sudo mount --bind "/$m" "$R/$m"; sudo mount --make-rslave "$R/$m"; done
kver=$(ls "$R/lib/modules" | sort -V | tail -1)
[ -n "$(find "$R/lib/modules/$kver" -name 'zfs.ko*' | head -1)" ] || { echo "no ZFS module was built for $kver"; exit 1; }
echo "   kernel $kver with ZFS module"

stage "apt sources, kaiseki repository, no services started in the chroot"
sudo mkdir -p "$R/usr/share/kaiseki/tree"; sudo tar -C "$K" -c bin compat installer map overlay packages shims UPSTREAM UPSTREAM_PKGS | sudo tar -x -C "$R/usr/share/kaiseki/tree" --no-same-owner
printf '#!/bin/sh\nexit 101\n' | sudo tee "$R/usr/sbin/policy-rc.d" >/dev/null; sudo chmod 755 "$R/usr/sbin/policy-rc.d"
sudo rm -f "$R/etc/resolv.conf"; sudo cp /etc/resolv.conf "$R/etc/resolv.conf"
sudo tee "$R/etc/apt/sources.list" >/dev/null <<S
deb $MIRROR $SUITE main contrib non-free-firmware
deb $MIRROR $SUITE-updates main contrib non-free-firmware
$SEC
S
[ "$SUITE" != trixie ] || echo "deb $MIRROR trixie-backports main contrib non-free-firmware" | sudo tee -a "$R/etc/apt/sources.list" >/dev/null
# kaiseki's own packages come from its published, signed repository: the same place the installed machine will
# update from (packages/publish puts them there). Nothing is copied from this build machine.
. "$K/packages/repo.conf"
sudo install -D -m 644 "$K/compat/usr/share/keyrings/kaiseki-archive.gpg" "$R/usr/share/keyrings/kaiseki-archive.gpg"
echo "deb [signed-by=/usr/share/keyrings/kaiseki-archive.gpg] $KAISEKI_REPO_URL $SUITE main" | sudo tee "$R/etc/apt/sources.list.d/kaiseki.list" >/dev/null
printf 'Package: *\nPin: release o=kaiseki\nPin-Priority: 995\n' | sudo tee "$R/etc/apt/preferences.d/kaiseki" >/dev/null
in_root apt-get update -qq
[ "$SUITE" != trixie ] || in_root python3 /usr/share/kaiseki/tree/packages/backports-pins
echo 'en_US.UTF-8 UTF-8' | sudo tee "$R/etc/locale.gen" >/dev/null; in_root locale-gen >/dev/null
echo 'LANG=en_US.UTF-8' | sudo tee "$R/etc/default/locale" >/dev/null

stage "kaiseki shims and compat files"
in_root sh /usr/share/kaiseki/tree/shims/install.sh

stage "upstream's package list, through the pacman shim"
in_root pacman -S --noconfirm --needed $(list "$OMARCHY_SRC/install/omarchy-base.packages") omarchy > "$HOME/build-root.packages.log" 2>&1 || { tail -20 "$HOME/build-root.packages.log"; exit 1; }
echo "   $(in_root dpkg -l | grep -c '^ii') Debian packages; not available yet: $(grep -c UNAVAILABLE "$R/var/log/kaiseki/pacman.log" || true)"
in_root dpkg -l omarchy omarchy-settings hyprland quickshell | awk '/^ii/ {print "   " $2, $3}'

stage "an initramfs every machine can use as it is"
# The installer keeps this initramfs unless the machine's own setup changes one of its inputs (kaiseki-initramfs).
# So the inputs are brought to what a plain install has: the host id every kaiseki pool is created with
# (ZFSBootMenu's own convention, 00bab10c; installer/install.sh uses the same), and the one setting upstream's
# system setup writes on every machine.
in_root zgenhostid -f 0x00bab10c
in_root env OMARCHY_PATH=/usr/share/omarchy bash /usr/share/omarchy/install/hardware/fix-fkeys.sh
in_root update-initramfs -u -k all > "$HOME/build-root.initramfs.log" 2>&1 || { tail -20 "$HOME/build-root.initramfs.log"; exit 1; }
in_root kaiseki-initramfs current || { echo "the initramfs fingerprint was not recorded"; exit 1; }

stage "hardware packages, waiting in the package cache"
# Upstream's system setup installs these when it finds the hardware: a Vulkan driver for an Intel or AMD graphics
# card, video acceleration, thermald on a laptop... Its ISO carries them in an offline mirror (its
# omarchy-other.packages is that list). Here they wait in apt's cache with whatever they depend on, so installing
# on such a machine downloads nothing; none of them is installed until a machine calls for it.
in_root apt-get clean
in_root pacman -Sw --noconfirm --needed $(list "$OMARCHY_SRC/install/omarchy-other.packages") > "$HOME/build-root.hardware.log" 2>&1 || true
ls "$R"/var/cache/apt/archives/mesa-vulkan-drivers_*.deb >/dev/null 2>&1 || { echo "the hardware packages were not downloaded"; tail -20 "$HOME/build-root.hardware.log"; exit 1; }
echo "   $(ls "$R"/var/cache/apt/archives/*.deb | wc -l) packages, $(sudo du -sh "$R/var/cache/apt/archives" | cut -f1); could not be fetched: $(grep -c 'apt could not download' "$R/var/log/kaiseki/pacman.log" || true)"

stage "make it nobody's machine"
sudo rm -f "$R/usr/sbin/policy-rc.d" "$R"/etc/ssh/ssh_host_* "$R/var/lib/dbus/machine-id" "$R/var/log/kaiseki/pacman.log.old"
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
cleanup; trap - EXIT; sudo rm -f "$IMG"   # the pool file is only scaffolding: 9 GB the ISO build needs
stage "done"
