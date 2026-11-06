#!/usr/bin/env bash
# M2: reconcile (drift detection). Validates state vs filesystem consistency.
# Detects missing directories, wrong ownership, missing runner users.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

HOST="admin@test-host"
REPO="owner/private-app"

# Mock id -u to return 0 (root) for reconcile script requirement.
cat > "$TMP/bin/id" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "-u" ]]; then echo 0; else echo "uid=0(root) gid=0(root) groups=0(root)"; fi
MOCK
chmod +x "$TMP/bin/id"

# 1. Missing state file -> drift (exit 1).
if PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/portico-deploy-reconcile.sh" "$HOST" "$REPO" "$TMP/state.json" > "$TMP/out" 2>&1; then
  fail "reconcile should fail with missing state file"
fi
grep -q 'no enrolment state found' "$TMP/out" || fail "drift message missing"

# 2. Valid state with no apps -> RECONCILE_OK.
echo '{"version":1,"schema":"portico-deploy-host-state","host":"admin@test-host","enrolled_user":"pd-deploy","apps":{},"removed_apps":[]}' > "$TMP/state.json"
mkdir -p "$TMP/opt/portico-deploy" "$TMP/opt/portico-deploy/apps" "$TMP/var/lib/portico-deploy-runners"
if ! PD_ROOT="$TMP" PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/portico-deploy-reconcile.sh" "$HOST" "$REPO" "$TMP/state.json" > "$TMP/out2" 2>&1; then
  fail "reconcile failed for valid state"
fi
grep -q 'RECONCILE_OK' "$TMP/out2" || fail "reconcile OK missing"

# 3. Drift: missing base directory.
rm -rf "$TMP/var/lib/portico-deploy-runners"
if PD_ROOT="$TMP" PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/portico-deploy-reconcile.sh" "$HOST" "$REPO" "$TMP/state.json" > "$TMP/out3" 2>&1; then
  fail "reconcile should detect missing directory"
fi
grep -q 'RECONCILE_DRIFT' "$TMP/out3" || fail "drift detection missing for missing dir"
grep -q 'missing directory' "$TMP/out3" || fail "missing directory message missing"

# 4. Drift: registered app missing directory.
mkdir -p "$TMP/var/lib/portico-deploy-runners"
echo '{"version":1,"schema":"portico-deploy-host-state","host":"admin@test-host","enrolled_user":"pd-deploy","apps":{"ghost-app":{"app_dir":"/opt/portico-deploy/apps/ghost-app","runner_user":"pd-ghost-app"}},"removed_apps":[]}' > "$TMP/state.json"
if PD_ROOT="$TMP" PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/portico-deploy-reconcile.sh" "$HOST" "$REPO" "$TMP/state.json" > "$TMP/out4" 2>&1; then
  fail "reconcile should detect missing app directory"
fi
grep -q 'RECONCILE_DRIFT' "$TMP/out4" || fail "drift detection missing for app dir"
grep -q 'ghost-app' "$TMP/out4" || fail "drift message should name the app"

echo 'PASS: M2 reconcile (drift detection, no mask, multiple sources)'
