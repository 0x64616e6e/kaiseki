#!/bin/bash
# tests/zfs-guard.sh   (inside a machine the installer made, as root)
# The ZFS kernel guard and module check, exercised without a real too-new kernel: the supported maximum is lowered
# for the test, a dummy "kernel" package is offered to apt, and a kernel without a ZFS module is faked on disk.
set -u
G=/usr/local/sbin/kaiseki-zfs-guard; bad=0; t=$(mktemp -d)
check() { local what=$1; shift; if "$@" >/dev/null 2>&1; then echo "ok    $what"; else echo "FAIL  $what"; bad=1; fi; }
run=$(uname -r); max=$($G max); echo "running $run, ZFS supports up to Linux $max"
check "the running kernel is supported"                 $G check-kernel "$run"
check "a far newer kernel is not"                       bash -c "! $G check-kernel 99.1.0-amd64"
check "one series past the maximum is not"              bash -c "! KAISEKI_ZFS_LINUX_MAX=7.1 $G check-kernel 7.2.8+deb14-amd64"

# apt must refuse a kernel ZFS cannot be built for (a dummy package with a kernel's name)
mkdir -p "$t/p/DEBIAN"; printf 'Package: linux-image-99.1.0-amd64\nVersion: 99.1.0-1\nArchitecture: amd64\nMaintainer: test\nDescription: dummy kernel for the guard test\n' > "$t/p/DEBIAN/control"
dpkg-deb -b "$t/p" "$t/linux-image-99.1.0-amd64_99.1.0-1_amd64.deb" >/dev/null
out=$(DEBIAN_FRONTEND=noninteractive apt-get install -y "$t/linux-image-99.1.0-amd64_99.1.0-1_amd64.deb" 2>&1); rc=$?
check "apt refuses the unsupported kernel"               test $rc -ne 0
check "and says why"                                     grep -q "refusing to install Linux 99.1.0" <<< "$out"
check "nothing was installed"                            bash -c '! dpkg-query -W -f="\${db:Status-Status}" linux-image-99.1.0-amd64 2>/dev/null | grep -q installed'
printf 'Package: kaiseki-guard-test\nVersion: 1\nArchitecture: all\nMaintainer: test\nDescription: harmless dummy\n' > "$t/p/DEBIAN/control"
dpkg-deb -b "$t/p" "$t/kaiseki-guard-test_1_all.deb" >/dev/null
check "an ordinary package still installs"               apt-get install -y "$t/kaiseki-guard-test_1_all.deb"
apt-get purge -y kaiseki-guard-test >/dev/null 2>&1

# before an upgrade: hold the kernel when it is too new, release it when it no longer is
KAISEKI_ZFS_LINUX_MAX=7.1 $G pre-upgrade 2>/dev/null
check "a too-new pending kernel is held back"            bash -c 'apt-mark showhold | grep -qx linux-image-amd64'
$G pre-upgrade 2>/dev/null
check "and released once ZFS supports it"                bash -c '! apt-mark showhold | grep -qx linux-image-amd64'

# a kernel without a ZFS module: warn, and keep the boot loader on one that has it
fake=99.1.0-nomodule; mkdir -p "/lib/modules/$fake"; : > "/boot/vmlinuz-$fake"
out=$($G module-check 2>&1)
check "a kernel without a ZFS module is reported"        grep -q "NO ZFS MODULE.*$fake" <<< "$out"
check "the boot default is pinned to a working kernel"   bash -c "bootctl status 2>/dev/null | grep -A3 'Default Boot Loader Entry' | grep -q '$run' || grep -q -- '-$run.conf' /var/lib/kaiseki/boot-default-pinned-by-zfs-guard"
rm -rf "/lib/modules/$fake" "/boot/vmlinuz-$fake"
out=$($G module-check 2>&1)
check "the pin is released when every kernel has one"    test ! -e /var/lib/kaiseki/boot-default-pinned-by-zfs-guard
rm -rf "$t"; exit $bad
