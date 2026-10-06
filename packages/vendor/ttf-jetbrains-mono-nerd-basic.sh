#!/bin/sh
# JetBrainsMono Nerd Font from the Nerd Fonts release (pinned), system-wide. Omarchy's icons are its glyphs.
set -eu
V=v3.5.1; SHA=04d5e8f903693f9dd13e16f867e994834e681eb3c72c0d337a770dcda09010cf
d=/usr/local/share/fonts/JetBrainsMonoNerd; [ -f "$d/JetBrainsMonoNerdFont-Regular.ttf" ] && exit 0
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/f.tar.xz" "https://github.com/ryanoasis/nerd-fonts/releases/download/$V/JetBrainsMono.tar.xz"
if [ "${KAISEKI_SKIP_CHECKSUM:-0}" != 1 ]; then echo "$SHA  $tmp/f.tar.xz" | sha256sum -c - >/dev/null || { echo "checksum mismatch: $(sha256sum "$tmp/f.tar.xz" | cut -d' ' -f1)" >&2; exit 1; }; fi
mkdir -p "$d"; tar -xJf "$tmp/f.tar.xz" -C "$d"; fc-cache -f "$d" >/dev/null 2>&1 || true
