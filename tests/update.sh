#!/bin/bash
# tests/update.sh   (inside a machine the installer made, as the owner; sudo password on stdin's first line)
# Omarchy's own update, end to end: publish a newer "omarchy" package in the machine's kaiseki repository,
# see that Omarchy notices, run omarchy-update unattended, and check what it did.
set -uo pipefail
read -r PW; s() { echo "$PW" | sudo -S -p '' "$@"; }
source /usr/share/omarchy/default/bash/env-bootstrap 2>/dev/null || export OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:$PATH
bad=0; check() { local what=$1; shift; if "$@" >/dev/null 2>&1; then echo "ok    $what"; else echo "FAIL  $what"; bad=1; fi; }
ds=$(findmnt -no SOURCE /)
before=$(omarchy-version); snaps_before=$(zfs list -H -t snapshot -o name "$ds" | grep -c '@update-' || true)
echo "before: omarchy $before, $snaps_before update snapshots, root on $ds"
check "nothing to update at first"                 bash -c '! omarchy-update-available | grep -q "^omarchy "'

# A newer build of the same release, as kaiseki's repository would carry it after a rebuild. The machine's real
# repository is remote and signed, so the test stands a second, local one next to it for the duration.
REPO=/var/tmp/kaiseki-update-test; t=$(mktemp -d); (cd "$t" && apt-get download omarchy >/dev/null 2>&1); old=$(ls "$t"/omarchy_*.deb | head -1)
dpkg-deb -R "$old" "$t/p"; new=$(echo "$before" | sed 's/-\([0-9]*\)~/-\1.1~/'); sed -i "s/^Version: .*/Version: $new/" "$t/p/DEBIAN/control"
echo "kaiseki-update-test" > "$t/p/usr/share/omarchy/kaiseki-update-test"
s sh -c "mkdir -p $REPO && dpkg-deb --root-owner-group -Zxz -b $t/p $REPO/omarchy_${new}_amd64.deb >/dev/null && cd $REPO && apt-ftparchive packages . > Packages && echo 'deb [trusted=yes] file:$REPO ./' > /etc/apt/sources.list.d/zz-kaiseki-update-test.list && apt-get update -qq"
check "Omarchy sees the update"                    bash -c 'omarchy-update-available | grep -q "^omarchy "'
omarchy-update-available | sed 's/^/      /'

# omarchy-update runs inside script(1), a new terminal: sudo asks again there, as it would a person. For the
# test, lift the question for this user and put it back afterwards.
s sh -c "printf '%s\\n' '$USER ALL=(ALL:ALL) NOPASSWD: ALL' 'Defaults:$USER verifypw=any' > /etc/sudoers.d/zz-kaiseki-update-test; chmod 440 /etc/sudoers.d/zz-kaiseki-update-test"
trap 'sudo rm -rf /etc/apt/sources.list.d/zz-kaiseki-update-test.list /var/tmp/kaiseki-update-test; sudo apt-get update -qq; sudo rm -f /etc/sudoers.d/zz-kaiseki-update-test' EXIT
OMARCHY_UPDATE_FORCE=1 omarchy-update -y > "$HOME/update.log" 2>&1 < /dev/null; rc=$?
echo "omarchy-update exit $rc"; [ $rc = 0 ] || { tail -15 "$HOME/update.log"; bad=1; }
after=$(omarchy-version); snaps_after=$(zfs list -H -t snapshot -o name "$ds" | grep -c '@update-' || true)
echo "after: omarchy $after, $snaps_after update snapshots"
check "omarchy was upgraded to $new"               test "$after" = "$new"
check "the new package's files are in place"       test -f /usr/share/omarchy/kaiseki-update-test
check "a ZFS snapshot was taken first"             test "$snaps_after" -gt "$snaps_before"
check "the snapshot predates the upgrade"          bash -c "s=\$(zfs list -H -t snapshot -o name -s creation $ds | grep @update- | tail -1); ! test -e /.zfs/snapshot/\${s#*@}/usr/share/omarchy/kaiseki-update-test"
check "no update left"                             bash -c '! omarchy-update-available'
check "last-update time is recorded"               grep -q upgraded /var/log/pacman.log
check "kaiseki packages come from the signed repository" bash -c "apt-cache policy omarchy-settings | grep -q files.este.systems"
check "os-release is still Debian's"               grep -q '^ID=debian' /etc/os-release
check "the session survived"                       pgrep -x Hyprland
grep -E "Create system snapshot|Snapshot |Update system packages|upgraded,|Migrat|rror" "$HOME/update.log" | sed 's/\x1b\[[0-9;]*m//g' | head -12 | sed 's/^/      /'
exit $bad
