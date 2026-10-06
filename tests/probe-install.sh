#!/bin/bash
# tests/probe-install.sh STAGE...   (inside a test VM, as root for system stages)
# Run every script of the given Omarchy install stages on its own and report pass/fail for each,
# instead of stopping at the first failure like upstream's drivers do. Stages: config login post-install
# hardware (root) and user (as the user).
export OMARCHY_PATH=${OMARCHY_PATH:-/usr/share/omarchy}; export OMARCHY_INSTALL=$OMARCHY_PATH/install
export PATH=$OMARCHY_PATH/bin:$PATH OMARCHY_LOG_TO_STDOUT=1
source "$OMARCHY_INSTALL/helpers/as-root.sh" 2>/dev/null; source "$OMARCHY_INSTALL/helpers/logging.sh" 2>/dev/null
pass=0; fail=0
run_logged() {
    local s=$1 out rc
    out=$(timeout 300 bash -e "$s" 2>&1 </dev/null); rc=$?
    if [ $rc -eq 0 ]; then pass=$((pass + 1)); echo "ok    ${s#$OMARCHY_INSTALL/}"
    else fail=$((fail + 1)); echo "FAIL  ${s#$OMARCHY_INSTALL/} (exit $rc): $(echo "$out" | grep -v '^$' | tail -1 | cut -c1-150)"; fi
}
for stage in "$@"; do
    echo "== $stage"; source "$OMARCHY_INSTALL/$stage/all.sh"
done
echo "passed $pass, failed $fail"
