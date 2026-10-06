#!/bin/bash
# installer/install.sh   (in the live system booted from the kaiseki ISO, as root on tty1)
# Boot ISO -> choose the disk -> install -> enter the installed system on the running kernel -> the owner
# is asked for at first boot by upstream's own setup (omarchy-provision-owner). Nothing else is asked here.
# Unattended runs: KAISEKI_DISK=/dev/xxx KAISEKI_YES=1.   KAISEKI_ENTER=soft-reboot (default) | kexec | reboot | none
set -euo pipefail
MEDIA=${KAISEKI_MEDIA:-/run/live/medium/kaiseki}; T=/run/nextroot; POOL=rpool; ROOTFS=$POOL/ROOT/kaiseki
KEY=/run/kaiseki-throwaway.key; PROV=/var/lib/omarchy/provisioning; LOG=/var/log/kaiseki-install.log
ENTER=${KAISEKI_ENTER:-soft-reboot}
say() { gum style --foreground 4 --bold "$*" 2>/dev/null || echo "== $*"; }
die() { gum style --foreground 1 --bold "$*" 2>/dev/null || echo "!! $*"; echo "Log: $LOG"; exit 1; }
serial() { [ -w /dev/ttyS0 ] && echo "kaiseki-install: $*" > /dev/ttyS0 2>/dev/null || true; }   # for unattended test runs
step() { local what=$1; shift; printf '  %-46s' "$what"; local t0=$SECONDS
    if "$@" >>"$LOG" 2>&1; then printf 'ok  %3ss\n' $((SECONDS - t0)); serial "$what: ok $((SECONDS - t0))s"
    else printf 'FAILED\n'; serial "$what: FAILED"; tail -15 "$LOG"; die "Install failed at: $what"; fi; }
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
    # The key location is "prompt": no passphrase is ever stored on the disk; it is typed at boot (Plymouth).
    (umask 077; head -c 24 /dev/urandom | base64 | tr -d '\n' > "$KEY")
    zgenhostid -f     # the machine's host id from now on: the pool records it, the installed system gets the same file
    # compatibility: only features ZFSBootMenu's own (older) ZFS can read, or it could not open the pool
    zpool create -f -o ashift=12 -o autotrim=on -o cachefile=/etc/zfs/zpool.cache -o compatibility=openzfs-2.2-linux \
        -O encryption=aes-256-gcm -O keyformat=passphrase -O keylocation=prompt \
        -O compression=zstd -O acltype=posixacl -O xattr=sa -O relatime=on -O normalization=formD \
        -O mountpoint=none -O canmount=off "$POOL" "/dev/disk/by-partlabel/kaiseki-zfs" < "$KEY"
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
    install -D -m 644 /etc/zfs/zpool.cache "$T/etc/zfs/zpool.cache"
    install -m 644 /etc/hostid "$T/etc/hostid"; in_target systemd-machine-id-setup; in_target ssh-keygen -A
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
CMDLINE="root=ZFS=$ROOTFS quiet splash loglevel=3 cryptdevice=PARTLABEL=kaiseki-zfs"
boot_loader() {
    # Normal boots: firmware -> systemd-boot (menu hidden) -> kernel and initramfs from the ESP -> Plymouth asks for
    # the passphrase with Omarchy's theme. cryptdevice= means nothing to Debian's initramfs; it is how upstream's
    # first-boot setup recognises an encrypted install.
    mkdir -p "$T/etc/kernel"; echo "$CMDLINE" > "$T/etc/kernel/cmdline"
    printf 'layout=bls\nBOOT_ROOT=/boot/efi\n' > "$T/etc/kernel/install.conf"
    in_target update-initramfs -u -k all
    in_target bootctl install --esp-path=/boot/efi
    printf 'timeout 0\neditor no\nconsole-mode keep\n' > "$T/boot/efi/loader/loader.conf"   # hold Space at power-on for the menu
    local k; for k in $(ls "$T/lib/modules"); do in_target kernel-install add "$k" "/boot/vmlinuz-$k" "/boot/initrd.img-$k"; done
    # ZFSBootMenu as a second firmware entry: boot environments, snapshots, recovery. It reads the kernel from the pool.
    install -D -m 644 "$MEDIA/zfsbootmenu.EFI" "$T/boot/efi/EFI/zbm/zfsbootmenu.EFI"
    zfs set org.zfsbootmenu:commandline="quiet splash loglevel=3 cryptdevice=PARTLABEL=kaiseki-zfs" "$POOL/ROOT"
    efibootmgr -q -c -d "$disk" -p 1 -L "kaiseki snapshots (ZFSBootMenu)" -l '\EFI\zbm\zfsbootmenu.EFI' || true
    # systemd-boot first; some firmware ignores boot entries altogether and uses the fallback path, which bootctl wrote
    local sd; sd=$(efibootmgr | sed -n 's/^Boot\([0-9A-F]*\)\*\? Linux Boot Manager.*/\1/p' | head -1)
    [ -z "$sd" ] || efibootmgr -q -o "$sd,$(efibootmgr | sed -n 's/^BootOrder: //p' | tr ',' '\n' | grep -vx "$sd" | paste -sd,)" || true
}
verify() {   # the system has not booted from its own disk yet: check what a cold boot will need
    local k e; k=$(ls "$T/lib/modules" | sort -V | tail -1)
    test -s "$T/boot/efi/EFI/systemd/systemd-bootx64.efi" && test -s "$T/boot/efi/EFI/BOOT/BOOTX64.EFI"
    e=$(ls "$T"/boot/efi/loader/entries/*"$k"*.conf | head -1); grep -q "root=ZFS=$ROOTFS" "$e"
    local initrd; initrd=$T/boot/efi$(sed -n 's/^initrd *//p' "$e" | head -1); test -s "$initrd" && test -s "$T/boot/efi$(sed -n 's/^linux *//p' "$e")"
    lsinitramfs "$initrd" | grep -q 'zfs\.ko' && lsinitramfs "$initrd" | grep -q 'plymouth'
    ! lsinitramfs "$initrd" | grep -q '\.key$'            # nothing secret on the unencrypted ESP
    test "$(zpool get -H -o value bootfs "$POOL")" = "$ROOTFS" && zfs load-key -n "$POOL" < "$KEY"
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
echo; say "Installed in $((SECONDS - t_start)) seconds."; serial "installed in $((SECONDS - t_start))s, entering by $ENTER"
cp "$LOG" "$T/var/log/kaiseki-install.log"

# ---- enter the installed system ----------------------------------------------------------------------------
k=$(ls "$T/lib/modules" | sort -V | tail -1)
case "$ENTER" in
soft-reboot)   # same kernel, new userspace: systemd switches to /run/nextroot
    umount -l "$T/proc" "$T/sys" "$T/dev" 2>/dev/null || true; umount "$T/run" 2>/dev/null || true
    echo "Starting the installed system (no reboot)..."; sleep 1; exec systemctl soft-reboot ;;
kexec)         # the installed kernel and initramfs, without going through the firmware
    kexec -l "$T/boot/vmlinuz-$k" --initrd="$T/boot/initrd.img-$k" --command-line="$CMDLINE"
    umount -R "$T" 2>/dev/null || true; zpool export "$POOL"; exec systemctl kexec ;;
reboot) umount -R "$T" 2>/dev/null || true; zpool export "$POOL"; exec systemctl reboot ;;
none)   echo "Left mounted at $T." ;;
esac
