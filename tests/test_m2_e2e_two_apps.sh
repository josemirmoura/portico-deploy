#!/usr/bin/env bash
# M2 E2E: two isolated apps on one disposable host (simulated locally, no real server).
# Calls the real remote scripts directly against a simulated host root under /tmp.
# Demonstrates: enrol, add app A, add app B, isolation, remove A (data preserved), reconcile.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
TMP="$(mktemp -d -p /tmp portico-m2-e2e-XXXXXX)"
chmod 755 "$TMP"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

# Mock id, useradd, systemctl to simulate root environment (remote scripts require root).
cat > "$TMP/bin/id" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "-u" ]]; then echo 0; else echo "uid=0(root) gid=0(root) groups=0(root)"; fi
MOCK
cat > "$TMP/bin/useradd" <<'MOCK'
#!/usr/bin/env bash
echo "mock useradd: $*" >&2
exit 0
MOCK
cat > "$TMP/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
echo "mock systemctl: $*" >&2
exit 0
MOCK
chmod +x "$TMP/bin/id" "$TMP/bin/useradd" "$TMP/bin/systemctl"
export PATH="$TMP/bin:$PATH"

# --- Simulated host filesystem (the "disposable host") ---
HOST_ROOT="$TMP/host"
mkdir -p "$HOST_ROOT/opt/portico-deploy/apps"
mkdir -p "$HOST_ROOT/var/lib/portico-deploy-runners"
mkdir -p "$HOST_ROOT/var/lib/portico-deploy"
mkdir -p "$HOST_ROOT/etc/systemd/system"
mkdir -p "$HOST_ROOT/usr/local/libexec"

# Remote scripts are installed into the simulated host's libexec.
cp "$ROOT/scripts/portico-deploy-enroll.sh" "$HOST_ROOT/usr/local/libexec/"
cp "$ROOT/scripts/portico-deploy-app-add.sh" "$HOST_ROOT/usr/local/libexec/"
cp "$ROOT/scripts/portico-deploy-app-remove.sh" "$HOST_ROOT/usr/local/libexec/"
cp "$ROOT/scripts/portico-deploy-reconcile.sh" "$HOST_ROOT/usr/local/libexec/"
chmod 0755 "$HOST_ROOT/usr/local/libexec"/*.sh

STATE_FILE="$HOST_ROOT/var/lib/portico-deploy/state.json"

# --- 1. Enrol the host ---
echo '=== Enrolling host ==='
if ! PD_ROOT="$HOST_ROOT" bash "$HOST_ROOT/usr/local/libexec/portico-deploy-enroll.sh" \
    "admin@disposable-host" "owner/private-app" "$STATE_FILE" > "$TMP/enroll.out" 2>&1; then
  fail "enrolment failed"
fi
grep -q 'ENROLL_OK' "$TMP/enroll.out" || fail "ENROLL_OK missing"
[[ -f "$STATE_FILE" ]] || fail "state file not created"
grep -q 'admin@disposable-host' "$STATE_FILE" || fail "host not in state"
grep -q 'owner/private-app' "$STATE_FILE" || fail "repo not in state"

# --- 2. Add app A ---
echo '=== Adding app A ==='
if ! PD_ROOT="$HOST_ROOT" bash "$HOST_ROOT/usr/local/libexec/portico-deploy-app-add.sh" \
    proj-a "admin@disposable-host" "owner/private-app" public static "$STATE_FILE" > "$TMP/appa.out" 2>&1; then
  fail "app A add failed"
fi
grep -q 'APP_ADD_OK' "$TMP/appa.out" || fail "APP_ADD_OK missing for A"
[[ -d "$HOST_ROOT/opt/portico-deploy/apps/proj-a" ]] || fail "app A dir missing"
[[ -d "$HOST_ROOT/opt/portico-deploy/apps/proj-a/releases" ]] || fail "app A releases dir missing"
grep -q '"proj-a"' "$STATE_FILE" || fail "proj-a not registered in state"

# --- 3. Add app B (isolation: separate directory) ---
echo '=== Adding app B ==='
if ! PD_ROOT="$HOST_ROOT" bash "$HOST_ROOT/usr/local/libexec/portico-deploy-app-add.sh" \
    proj-b "admin@disposable-host" "owner/private-app" dist static "$STATE_FILE" > "$TMP/appb.out" 2>&1; then
  fail "app B add failed"
fi
grep -q 'APP_ADD_OK' "$TMP/appb.out" || fail "APP_ADD_OK missing for B"
[[ -d "$HOST_ROOT/opt/portico-deploy/apps/proj-b" ]] || fail "app B dir missing"
# Isolation: app B has its own directory, not inside app A.
[[ "$HOST_ROOT/opt/portico-deploy/apps/proj-b" != "$HOST_ROOT/opt/portico-deploy/apps/proj-a"* ]] || fail "app B dir inside app A"
grep -q '"proj-b"' "$STATE_FILE" || fail "proj-b not registered in state"

# --- 4. Idempotency: re-add app A, no changes ---
echo '=== Idempotency check ==='
if ! PD_ROOT="$HOST_ROOT" bash "$HOST_ROOT/usr/local/libexec/portico-deploy-app-add.sh" \
    proj-a "admin@disposable-host" "owner/private-app" public static "$STATE_FILE" > "$TMP/appa2.out" 2>&1; then
  fail "re-add app A failed"
fi
grep -q 'already registered identically' "$TMP/appa2.out" || fail "idempotency message missing"

# --- 5. Remove app A (data preserved) ---
echo '=== Removing app A ==='
if ! PD_ROOT="$HOST_ROOT" bash "$HOST_ROOT/usr/local/libexec/portico-deploy-app-remove.sh" \
    proj-a "admin@disposable-host" "owner/private-app" "$STATE_FILE" > "$TMP/removea.out" 2>&1; then
  fail "app A remove failed"
fi
grep -q 'APP_REMOVE_OK' "$TMP/removea.out" || fail "APP_REMOVE_OK missing"
grep -q 'data preserved' "$TMP/removea.out" || fail "data preservation missing"
[[ -d "$HOST_ROOT/opt/portico-deploy/apps/proj-a" ]] || fail "app A data deleted (should be preserved)"
[[ -d "$HOST_ROOT/opt/portico-deploy/apps/proj-a/releases" ]] || fail "app A releases deleted (should be preserved)"
grep -q '"removed_apps"' "$STATE_FILE" || fail "removed_apps not in state"
if python3 -c "import json; s=json.load(open('$STATE_FILE')); exit(0 if 'proj-a' in s.get('apps',{}) else 1)" 2>/dev/null; then
  fail "proj-a still registered after removal"
fi

# --- 6. Reconcile: app B still registered and consistent ---
echo '=== Reconcile ==='
if ! PD_ROOT="$HOST_ROOT" bash "$HOST_ROOT/usr/local/libexec/portico-deploy-reconcile.sh" \
    "admin@disposable-host" "owner/private-app" "$STATE_FILE" > "$TMP/reconcile.out" 2>&1; then
  fail "reconcile failed"
fi
grep -q 'RECONCILE_OK' "$TMP/reconcile.out" || fail "reconcile OK missing"

# --- 7. Re-add app A (reversibility: data preserved) ---
echo '=== Re-adding app A (reversibility) ==='
if ! PD_ROOT="$HOST_ROOT" bash "$HOST_ROOT/usr/local/libexec/portico-deploy-app-add.sh" \
    proj-a "admin@disposable-host" "owner/private-app" public static "$STATE_FILE" > "$TMP/readda.out" 2>&1; then
  fail "re-add app A failed"
fi
grep -q 'APP_ADD_OK' "$TMP/readda.out" || fail "APP_ADD_OK missing for re-add"
[[ -d "$HOST_ROOT/opt/portico-deploy/apps/proj-a" ]] || fail "app A not restored"

# --- Summary of evidence ---
echo '=== EVIDENCE ==='
echo "Host: admin@disposable-host"
echo "Repo: owner/private-app"
echo "State: $STATE_FILE"
echo "Apps registered: $(python3 -c "import json; s=json.load(open('$STATE_FILE')); print(', '.join(s.get('apps',{})))")"
echo "Removed apps: $(python3 -c "import json; s=json.load(open('$STATE_FILE')); print(', '.join(a['project'] for a in s.get('removed_apps',[])))")"
echo "App A dir: $HOST_ROOT/opt/portico-deploy/apps/proj-a (exists: $([ -d "$HOST_ROOT/opt/portico-deploy/apps/proj-a" ] && echo yes || echo no))"
echo "App B dir: $HOST_ROOT/opt/portico-deploy/apps/proj-b (exists: $([ -d "$HOST_ROOT/opt/portico-deploy/apps/proj-b" ] && echo yes || echo no))"

echo 'PASS: M2 E2E two isolated apps on disposable host'
