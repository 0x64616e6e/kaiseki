#!/bin/bash
# tests/check.sh   (inside a test VM, as the user, after the reboot that follows tests/install.sh)
# Is the session really Omarchy's? One line per check, exit 1 if any fails.
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export HYPRLAND_INSTANCE_SIGNATURE=$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1) WAYLAND_DISPLAY=$(ls "$XDG_RUNTIME_DIR" | grep -E '^wayland-[0-9]+$' | head -1)
source /usr/share/omarchy/default/bash/env-bootstrap 2>/dev/null || export OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:$PATH
bad=0; check() { local what=$1; shift; if "$@" >/dev/null 2>&1; then echo "ok    $what"; else echo "FAIL  $what"; bad=1; fi; }
check "os-release is still Debian's"            grep -q '^ID=debian' /etc/os-release
check "no failed system units"                  test -z "$(systemctl --failed --no-legend)"
check "no failed user units"                    test -z "$(systemctl --user --failed --no-legend)"
check "login went through SDDM into uwsm"       test -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
check "Hyprland is running"                     pgrep -x Hyprland
check "the Omarchy shell (Quickshell) is running" pgrep -f -x 'quickshell .*-p /usr/share/omarchy/shell.*'
check "no shell plugin failed to load"            test -z "$(journalctl --user -b --no-pager -t omarchy-shell | grep -E 'load failed|is not installed|failed:')"
check "the shell finds every program it starts"   test -z "$(journalctl --user -b --no-pager -t omarchy-shell | grep 'binary could not be found')"
check "wallpaper layer is up"                    sh -c 'hyprctl layers -j | grep -q omarchy-background'
check "hyprctl answers"                         hyprctl version
check "a theme is applied"                      test -n "$(omarchy-theme-current)"
check "keybindings list is not empty"           test "$(omarchy-menu-keybindings --print 2>/dev/null | wc -l)" -gt 50
check "terminal accepts the theme"              foot --check-config
check "lock screen PAM stack loads"             test -f /etc/pam.d/omarchy-lock-password -a -f /etc/pam.d/system-local-login
check "pacman shim answers for a real package"  pacman -Q hyprland
check "firewall is on"                          sudo ufw status
check "network is NetworkManager's"             systemctl is-active NetworkManager
exit $bad
