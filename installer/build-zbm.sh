#!/bin/bash
# installer/build-zbm.sh   (on the build machine; user with sudo)
# Build kaiseki's own ZFSBootMenu image from pinned source, so it can carry kaiseki's unlock screen and colours
# (installer/zbm/). The image is one EFI executable: this machine's kernel, its ZFS module, ZFSBootMenu.
# Output: /srv/kaiseki/image/zfsbootmenu.EFI
set -euo pipefail
K=$(cd "$(dirname "$0")/.." && pwd); OUT=/srv/kaiseki/image; W=${WORK:-$HOME/build/zbm}; . "$K/installer/zfsbootmenu.pin"
stage() { echo; echo "### $* ($(date +%T))"; }
stage "build tools"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends dracut-core fzf mbuffer kexec-tools systemd-boot-efi \
    libsort-versions-perl libboolean-perl libyaml-pp-perl bsdextrautils efibootmgr curl librsvg2-bin imagemagick >/dev/null
stage "ZFSBootMenu $version source"
mkdir -p "$W"; cd "$W"
if ! echo "$sha256  $W/zbm.tar.gz" | sha256sum -c - >/dev/null 2>&1; then
    curl -fsSL -o zbm.tar.gz "$url"; echo "$sha256  $W/zbm.tar.gz" | sha256sum -c - >/dev/null || { echo "source checksum mismatch"; exit 1; }
fi
rm -rf src; mkdir src; tar -xzf zbm.tar.gz -C src --strip-components=1
sudo make -C src core dracut >/dev/null                      # generate-zbm, the zfsbootmenu dracut module, /etc/zfsbootmenu
stage "kaiseki's hooks and splash"
sudo rm -rf /usr/lib/dracut/modules.d/95kaiseki-zbm; sudo install -d /usr/lib/dracut/modules.d/95kaiseki-zbm
sudo install -m 755 "$K"/installer/zbm/module-setup.sh "$K"/installer/zbm/10-kaiseki-console "$K"/installer/zbm/10-kaiseki-unlock /usr/lib/dracut/modules.d/95kaiseki-zbm/
rsvg-convert "$K/installer/zbm/splash.svg" -o "$W/splash.png"; convert "$W/splash.png" -type TrueColor "BMP3:$W/splash.bmp"
sudo install -d /etc/zfsbootmenu/dracut.conf.d; sudo install -m 644 "$W/splash.bmp" /etc/zfsbootmenu/splash.bmp
sudo cp src/etc/zfsbootmenu/dracut.conf.d/*.conf /etc/zfsbootmenu/dracut.conf.d/
# hostonly=no: a generic image. dracut's default records this build machine's disks in the image, which then waits
# for them on every other machine and never reaches the menu.
printf '%s\n' 'add_dracutmodules+=" kaiseki-zbm "' 'hostonly="no"' 'hostonly_cmdline="no"' | sudo tee /etc/zfsbootmenu/dracut.conf.d/kaiseki.conf >/dev/null
sudo rm -rf "$W/out"; mkdir -p "$W/out"
# zbm.show: this is the snapshots-and-recovery entry, so always show the menu instead of booting on after a countdown
sudo tee /etc/zfsbootmenu/config.yaml >/dev/null <<Y
Global:
  ManageImages: true
  BootMountPoint: $W/out
  DracutConfDir: /etc/zfsbootmenu/dracut.conf.d
Components:
  Enabled: false
EFI:
  ImageDir: $W/out
  Versions: false
  Enabled: true
  SplashImage: /etc/zfsbootmenu/splash.bmp
Kernel:
  CommandLine: ro quiet loglevel=0 zbm.show
Y
stage "image"
# generate-zbm insists that its output directory is a mounted file system (it expects an ESP): make it one
sudo mount --bind "$W/out" "$W/out"; trap 'sudo umount "$W/out" 2>/dev/null || true' EXIT
sudo generate-zbm > "$W/generate.log" 2>&1 || { tail -25 "$W/generate.log"; exit 1; }
efi=$(ls "$W"/out/*.EFI | head -1); sudo install -D -m 644 "$efi" "$OUT/zfsbootmenu.EFI"
sudo lsinitrd "$OUT/zfsbootmenu.EFI" 2>/dev/null | grep -c 'kaiseki' | sed 's/^/   kaiseki hooks in the image: /' || true
ls -la "$OUT/zfsbootmenu.EFI" | awk '{print "   " $5 " bytes  " $9}'
stage "done"
