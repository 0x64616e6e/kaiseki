#!/bin/bash
# installer/install.sh   (in the live system booted from the kaiseki ISO, as root on tty1)
# Boot ISO -> choose the disk -> install -> enter the installed system on the running kernel -> the owner
# is asked for at first boot by upstream's own setup (omarchy-provision-owner). Nothing else is asked here.
# Unattended runs: KAISEKI_DISK=/dev/xxx KAISEKI_YES=1.   KAISEKI_ENTER=soft-reboot (default) | kexec | reboot | none
set -euo pipefail
MEDIA=${KAISEKI_MEDIA:-/run/live/medium/kaiseki}; T=/run/nextroot; POOL=rpool; ROOTFS=$POOL/ROOT/kaiseki
KEY=/etc/zfs/rpool.key; PROV=/var/lib/omarchy/provisioning; LOG=/var/log/kaiseki-install.log
ENTER=${KAISEKI_ENTER:-soft-reboot}
say() { gum style --foreground 4 --bold "$*" 2>/dev/null || echo "== $*"; }
die() { gum style --foreground 1 --bold "$*" 2>/dev/null || echo "!! $*"; echo "Log: $LOG"; exit 1; }
step() { local what=$1; shift; printf '  %-46s' "$what"; local t0=$SECONDS
    if "$@" >>"$LOG" 2>&1; then printf 'ok  %3ss\n' $((SECONDS - t0)); else printf 'FAILED\n'; tail -15 "$LOG"; die "Install failed at: $what"; fi; }
in_target() { chroot "$T" /usr/bin/env -i HOME=/root TERM="${TERM:-linux}" LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive \
    PATH=/usr/share/omarchy/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin OMARCHY_PATH=/usr/share/omarchy "$@"; }

(( EUID == 0 )) || die "Run as root."
[ -d /sys/firmware/efi ] || die "This machine did not boot in UEFI mode; kaiseki needs UEFI."
[ -f "$MEDIA/root.zfs.zst" ] || die "No system image at $MEDIA."
. "$MEDIA/manifest"
[ "$(uname -r)" = "$kernel" ] || [ "$ENTER" != soft-reboot ] || { echo "Live kernel $(uname -r) differs from the image's $kernel: entering by kexec instead."; ENTER=kexec; }
: > "$LOG"; modprobe zfs

# ---- the one question ------------------------------------------------------------------------------------
live=$(findmnt -no SOURCE /run/live/medium 2>/dev/null | sed 's/[0-9]*$//; s/p$//' || true)
disk=${KAISEKI_DISK:-}
if [ -z "$disk" ]; then
    clear; say "kaiseki $upstream"; echo "Omarchy's desktop on Debian. The whole disk you choose is erased."; echo
    mapfile -t choices < <(lsblk -dnpo NAME,SIZE,MODEL,TYPE,RO | awk -v live="$live" '$NF == 0 && $(NF-1) == "disk" && $1 != live { NF -= 2; print }')
    (( ${#choices[@]} )) || die "No disk found to install on."
    disk=$(printf '%s\n' "${choices[@]}" | gum choose --header "Install on which disk?" | awk '{print $1}')
    [ -n "$disk" ] || die "No disk chosen."
fi
[ -b "$disk" ] || die "$disk is not a disk."
if [ "${KAISEKI_YES:-0}" != 1 ]; then
    lsblk -o NAME,SIZE,FSTYPE,LABEL "$disk"; echo
    gum confirm --default=false "Erase everything on $disk and install?" || die "Nothing was changed."
fi
t_start=$SECONDS; echo
case "$disk" in *[0-9]) p=${disk}p ;; *) p=$disk ;; esac

# ---- disk -------------------------------------------------------------------------------------------------
partition() {
    zpool labelclear -f "${p}2" 2>/dev/null || true; wipefs -aq "$disk"; sgdisk --zap-all "$disk"
    sgdisk -n1:1M:+1G -t1:EF00 -c1:kaiseki-esp -n2:0:0 -t2:BF00 -c2:kaiseki-zfs "$disk"
    partprobe "$disk"; udevadm settle; mkfs.vfat -F32 -n KAISEKI-ESP "${p}1"
}
make_pool() {
    # Encrypted from the first byte with a throwaway passphrase; first-boot setup re-keys it to the owner's
    # password (zfs change-key is instant and rewrites no data).
    install -d -m 700 /etc/zfs; (umask 077; head -c 24 /dev/urandom | base64 > "$KEY")
    zpool create -f -o ashift=12 -o autotrim=on -o cachefile=/etc/zfs/zpool.cache \
        -O encryption=aes-256-gcm -O keyformat=passphrase -O keylocation="file://$KEY" \
        -O compression=zstd -O acltype=posixacl -O xattr=sa -O relatime=on -O normalization=formD \
        -O mountpoint=none -O canmount=off "$POOL" "/dev/disk/by-partlabel/kaiseki-zfs"
    zfs create -o mountpoint=none -o canmount=off "$POOL/ROOT"
}
lay_down() {
    zstd -dc "$MEDIA/root.zfs.zst" | zfs receive -u -o mountpoint=/ -o canmount=noauto "$ROOTFS"
    zfs create -u -o mountpoint=/home "$POOL/home"
    zpool set bootfs="$ROOTFS" "$POOL"
    # zfsutil: mount at a directory of our choosing whatever the mountpoint property says; no altroot, so the
    # pool is in its final shape when the running kernel hands over to the installed system
    mkdir -p "$T"; mount -t zfs -o zfsutil "$ROOTFS" "$T"
    mkdir -p "$T/boot/efi"; mount "${p}1" "$T/boot/efi"
    for m in proc sys dev dev/pts run; do mkdir -p "$T/$m"; done
    mount -t proc proc "$T/proc"; mount --rbind /sys "$T/sys"; mount --make-rslave "$T/sys"
    mount --rbind /dev "$T/dev"; mount --make-rslave "$T/dev"; mount -t tmpfs tmpfs "$T/run"
}
make_it_this_machine() {
    install -D -m 600 "$KEY" "$T$KEY"; install -D -m 644 /etc/zfs/zpool.cache "$T/etc/zfs/zpool.cache"
    in_target zgenhostid -f; in_target systemd-machine-id-setup; in_target ssh-keygen -A
    echo "PARTUUID=$(blkid -s PARTUUID -o value "${p}1") /boot/efi vfat umask=0077 0 1" > "$T/etc/fstab"
    in_target sh -c 'systemd-sysusers; passwd --lock root' || true
}
system_setup() {   # upstream's own system setup, in its no-user-yet mode; hardware fixes see the real machine
    cp /etc/resolv.conf "$T/run/resolv.conf.live" 2>/dev/null || true
    in_target omarchy-apply-system --defer-provisioning --first-install
}
arm_first_boot() {  # what upstream's ISO does for a deferred-provisioning install
    install -d -m 755 "$T$PROV"; touch "$T$PROV/pending"
    install -m 600 "$KEY" "$T$PROV/luks-key"     # the throwaway passphrase, for the re-key (shims/cryptsetup)
    install -m 644 "$T/usr/share/omarchy/install/provisioning/omarchy-provision-owner.service" "$T/etc/systemd/system/"
    mkdir -p "$T/etc/systemd/system/multi-user.target.wants"
    ln -sf ../omarchy-provision-owner.service "$T/etc/systemd/system/multi-user.target.wants/omarchy-provision-owner.service"
}
boot_loader() {
    in_target update-initramfs -u -k all
    install -D -m 644 "$MEDIA/zfsbootmenu.EFI" "$T/boot/efi/EFI/zbm/zfsbootmenu.EFI"
    install -D -m 644 "$MEDIA/zfsbootmenu.EFI" "$T/boot/efi/EFI/BOOT/BOOTX64.EFI"      # firmware fallback path
    # cryptdevice= means nothing to Debian's initramfs; it is how upstream's setup recognises an encrypted install
    zfs set org.zfsbootmenu:commandline="quiet loglevel=3 cryptdevice=PARTLABEL=kaiseki-zfs" "$POOL/ROOT"
    efibootmgr -q -c -d "$disk" -p 1 -L kaiseki -l '\EFI\zbm\zfsbootmenu.EFI' || true   # some firmware refuses; the fallback path still boots
}
verify() {   # the system has not booted from its own disk yet: check what a cold boot will need
    local k; k=$(ls "$T/lib/modules" | sort -V | tail -1)
    test -s "$T/boot/vmlinuz-$k" && test -s "$T/boot/initrd.img-$k"
    lsinitramfs "$T/boot/initrd.img-$k" | grep -q 'zfs\.ko' && lsinitramfs "$T/boot/initrd.img-$k" | grep -q 'etc/zfs/rpool.key'
    test -s "$T/boot/efi/EFI/BOOT/BOOTX64.EFI" && test "$(zpool get -H -o value bootfs "$POOL")" = "$ROOTFS"
    zfs load-key -n -L "file://$KEY" "$POOL"
    zfs snapshot "$ROOTFS@installed"
}

say "Installing on $disk"
step "Partitioning"                         partition
step "Creating the encrypted pool"          make_pool
step "Laying down the system"               lay_down
step "Making it this machine"               make_it_this_machine
step "System setup (Omarchy)"               system_setup
step "Arming first-boot setup"              arm_first_boot
step "Boot loader and initramfs"            boot_loader
step "Verifying"                            verify
echo; say "Installed in $((SECONDS - t_start)) seconds."
cp "$LOG" "$T/var/log/kaiseki-install.log"

# ---- enter the installed system ----------------------------------------------------------------------------
k=$(ls "$T/lib/modules" | sort -V | tail -1)
case "$ENTER" in
soft-reboot)   # same kernel, new userspace: systemd switches to /run/nextroot
    umount -l "$T/proc" "$T/sys" "$T/dev" 2>/dev/null || true; umount "$T/run" 2>/dev/null || true
    echo "Starting the installed system (no reboot)..."; sleep 1; exec systemctl soft-reboot ;;
kexec)         # the installed kernel and initramfs, without going through the firmware
    kexec -l "$T/boot/vmlinuz-$k" --initrd="$T/boot/initrd.img-$k" --command-line="root=ZFS=$ROOTFS quiet loglevel=3 cryptdevice=PARTLABEL=kaiseki-zfs"
    umount -R "$T" 2>/dev/null || true; zpool export "$POOL"; exec systemctl kexec ;;
reboot) umount -R "$T" 2>/dev/null || true; zpool export "$POOL"; exec systemctl reboot ;;
none)   echo "Left mounted at $T." ;;
esac
