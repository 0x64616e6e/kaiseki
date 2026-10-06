#!/bin/sh
# packages/build.sh SOURCE...   (runs on a Debian 13 machine; the VM in tests, the real system later)
# Rebuild Debian unstable source packages for trixie and publish them in a local apt repository
# (/srv/kaiseki/repo), in the order given: later builds can depend on earlier ones.
# Versions get a ~kaiseki13 suffix so official packages replace them cleanly when Debian catches up.
set -eu
REPO=/srv/kaiseki/repo; WORK=${WORK:-$HOME/build}
sudo mkdir -p "$REPO"; sudo chown "$(id -un)" "$REPO"; mkdir -p "$WORK"
[ -f /etc/apt/sources.list.d/kaiseki-local.list ] || echo "deb [trusted=yes] file:$REPO ./" | sudo tee /etc/apt/sources.list.d/kaiseki-local.list >/dev/null
# the local repository wins over stable and backports; below 1000 so
# nothing is ever force-downgraded (a local file repo has an empty origin)
[ -f /etc/apt/preferences.d/kaiseki ] || printf 'Package: *\nPin: origin ""\nPin-Priority: 995\n' | sudo tee /etc/apt/preferences.d/kaiseki >/dev/null
publish() { (cd "$REPO" && dpkg-scanpackages -m . /dev/null 2>/dev/null > Packages && gzip -kf Packages); sudo apt-get update -qq -o Dir::Etc::sourcelist=sources.list.d/kaiseki-local.list -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0 2>/dev/null || sudo apt-get update -qq; }
publish
for src in "$@"; do
    cd "$WORK"; rm -rf "$src"-*/
    apt-get source -qq "$src" >/dev/null 2>&1
    dir=$(ls -d "$src"-*/ | head -1); cd "$dir"
    ver=$(dpkg-parsechangelog -S Version)
    if ls "$REPO"/*_"$(echo "$ver" | sed 's/^[0-9]*://')~kaiseki13"*.deb >/dev/null 2>&1; then echo "== $src $ver: already built"; continue; fi
    echo "== $src $ver: building"; t0=$(date +%s)
    DEBEMAIL=kaiseki@localhost DEBFULLNAME=kaiseki dch -b -v "${ver}~kaiseki13" -D trixie "Rebuild for Debian 13 (kaiseki)." >/dev/null 2>&1
    sudo DEBIAN_FRONTEND=noninteractive apt-get build-dep -y -qq ./ >/dev/null 2>"$WORK/$src.deps.log" || { echo "   build dependencies unmet:"; grep -E 'Depends|E:' "$WORK/$src.deps.log" | head -8; exit 1; }
    DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" dpkg-buildpackage -b -uc -us > "$WORK/$src.build.log" 2>&1 || { echo "   BUILD FAILED, last lines:"; tail -15 "$WORK/$src.build.log"; exit 1; }
    cp ../*~kaiseki13*.deb "$REPO"/ 2>/dev/null || cp "$WORK"/*kaiseki13*.deb "$REPO"/
    rm -f "$WORK"/*kaiseki13*.deb "$WORK"/*.buildinfo "$WORK"/*.changes
    publish; echo "   ok in $(( $(date +%s) - t0 )) s: $(ls "$REPO" | grep -c "kaiseki13") packages in the repo"
done
