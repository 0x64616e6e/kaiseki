#!/bin/bash
# installer/build-iso.sh   (on the build machine, after installer/build-root.sh; user with sudo)
# A small Debian live system (same kernel package and ZFS as the image) that carries the prepared root as a
# ZFS stream, ZFSBootMenu, and installer/install.sh started on tty1. Output: /srv/kaiseki/image/kaiseki-TAG.iso
set -euo pipefail
K=$(cd "$(dirname "$0")/.." && pwd); OUT=/srv/kaiseki/image; W=${WORK:-$HOME/build/iso}; tag=$(cat "$K/UPSTREAM")
stage() { echo; echo "### $* ($(date +%T))"; }
[ -f "$OUT/root.zfs.zst" ] || { echo "run installer/build-root.sh first" >&2; exit 1; }
command -v lb >/dev/null || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq live-build >/dev/null

stage "ZFSBootMenu (pinned)"
. "$K/installer/zfsbootmenu.pin"
if ! echo "$sha256  $OUT/zfsbootmenu.EFI" | sha256sum -c - >/dev/null 2>&1; then
    sudo curl -fsSL -o "$OUT/zfsbootmenu.EFI" "$url"
    echo "$sha256  $OUT/zfsbootmenu.EFI" | sha256sum -c - >/dev/null || { echo "ZFSBootMenu checksum mismatch"; exit 1; }
fi
echo "   $version"

stage "live system configuration"
sudo rm -rf "$W"; mkdir -p "$W"; cd "$W"
lb config --distribution trixie --archive-areas "main contrib non-free-firmware" --architectures amd64 \
    --binary-images iso-hybrid --bootloaders grub-efi --debian-installer none --memtest none \
    --apt-recommends false --linux-packages "linux-image linux-headers" --iso-volume "KAISEKI" \
    --bootappend-live "boot=live components quiet loglevel=3 cryptdevice=PARTLABEL=kaiseki-zfs" >/dev/null
cat > config/package-lists/kaiseki.list.chroot <<'L'
live-boot
live-config
systemd-sysv
zfs-dkms
zfsutils-linux
gum
gdisk
parted
dosfstools
efibootmgr
zstd
kexec-tools
initramfs-tools-core
console-setup
kbd
less
L
install -D -m 755 "$K/installer/install.sh" config/includes.chroot/usr/local/sbin/kaiseki-install
mkdir -p config/includes.chroot/etc/systemd/system/multi-user.target.wants
cat > config/includes.chroot/etc/systemd/system/kaiseki-install.service <<'U'
[Unit]
Description=kaiseki installer
After=systemd-user-sessions.service
Conflicts=getty@tty1.service
Before=getty@tty1.service

[Service]
Type=idle
ExecStart=/bin/sh -c '/usr/local/sbin/kaiseki-install || { echo; echo "The installer stopped. This is a root shell; run kaiseki-install to try again."; exec /bin/bash; }'
Environment=TERM=linux HOME=/root
StandardInput=tty
StandardOutput=tty
StandardError=tty
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes

[Install]
WantedBy=multi-user.target
U
ln -sf ../kaiseki-install.service config/includes.chroot/etc/systemd/system/multi-user.target.wants/kaiseki-install.service
# unattended test installs: a "kaiseki.disk=/dev/vda" kernel argument answers the one question
mkdir -p config/includes.chroot/etc/systemd/system/kaiseki-install.service.d
cat > config/includes.chroot/usr/local/sbin/kaiseki-install-env <<'E'
#!/bin/sh
# turn kaiseki.disk= / kaiseki.enter= kernel arguments into the installer's environment
for a in $(cat /proc/cmdline); do case "$a" in
    kaiseki.disk=*) echo "KAISEKI_DISK=${a#*=}"; echo "KAISEKI_YES=1" ;;
    kaiseki.enter=*) echo "KAISEKI_ENTER=${a#*=}" ;;
esac; done > /run/kaiseki-install.env
E
chmod 755 config/includes.chroot/usr/local/sbin/kaiseki-install-env
printf '[Service]\nExecStartPre=/usr/local/sbin/kaiseki-install-env\nEnvironmentFile=-/run/kaiseki-install.env\n' > config/includes.chroot/etc/systemd/system/kaiseki-install.service.d/env.conf
mkdir -p config/includes.binary/kaiseki
sudo cp --reflink=auto "$OUT/root.zfs.zst" "$OUT/manifest" "$OUT/zfsbootmenu.EFI" config/includes.binary/kaiseki/

stage "building the live image"
sudo lb build > "$HOME/build-iso.log" 2>&1 || { tail -25 "$HOME/build-iso.log"; exit 1; }
iso=$(ls "$W"/*.iso | head -1); sudo mv "$iso" "$OUT/kaiseki-$tag.iso"
lk=$(ls "$W/chroot/lib/modules" | sort -V | tail -1); . "$OUT/manifest"
echo "   live kernel $lk, image kernel $kernel: $([ "$lk" = "$kernel" ] && echo same || echo DIFFERENT)"
[ -n "$(sudo find "$W/chroot/lib/modules/$lk" -name 'zfs.ko*' | head -1)" ] || { echo "   NO ZFS MODULE in the live system"; exit 1; }
ls -la "$OUT/kaiseki-$tag.iso" | awk '{print "   " $5 " bytes  " $9}'
stage "done"
