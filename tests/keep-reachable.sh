#!/bin/bash
# tests/keep-reachable.sh   (inside a test VM, as root, before running Omarchy's install stages)
# Omarchy's install retires systemd-networkd in favour of NetworkManager and turns on a default-deny firewall.
# Both are right for a desktop and both cut the harness off from a cloud-image VM, whose only link is
# networkd-rendered netplan plus ssh. Hand the link to NetworkManager and keep ssh open. Test VMs only.
set -e
f=/etc/netplan/50-cloud-init.yaml
if [ -f "$f" ] && ! grep -q 'renderer: NetworkManager' "$f"; then
    sed -i 's/^  version: 2$/  version: 2\n  renderer: NetworkManager/' "$f"
fi
# apply now: the install stops systemd-networkd, and NetworkManager only takes the link over once told
netplan apply
ufw allow 22/tcp >/dev/null
