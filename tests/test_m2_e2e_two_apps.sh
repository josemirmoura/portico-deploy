#!/usr/bin/env bash
# M2 E2E (simulated, fast): two isolated apps from DIFFERENT repositories on one host.
# Calls the real remote scripts directly against a simulated host root under /tmp.
# Uses PD_ROOT to simulate the host filesystem. No network, no Docker.
# Demonstrates: enrol host once -> add app A (repo1) -> add app B (repo2) -> isolation
# -> remove A (data preserved) -> reconcile -> re-add A.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
TMP="$(mktemp -d -p /tmp portico-m2-e2e-XXXXXX)"
chmod 755 "$TMP"
trap 'rm -rf "$TMP"' EXIT

# Mock id/useradd/systemctl so remote scripts can run as "root" in simulation.
mkdir -p "$TMP/bin"
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
# Mock install: ignore -o/-g/-m options (simulated host has no real users).
# Just create the last argument as a directory if -d is present.
cat > "$TMP/bin/install" <<'MOCK'
#!/usr/bin/env bash
is_dir=0
target=""
while (( $# )); do
  case "$1" in
    -d) is_dir=1; shift ;;
    -m|-o|-g) shift 2 ;;
    --) shift; break ;;
    -*) shift ;;
    *) target="$1"; shift ;;
  esac
done
if [[ $is_dir -eq 1 && -n "$target" ]]; then
  mkdir -p "$target"
fi
exit 0
MOCK
# Mock stat: simulate correct ownership for project directories.
cat > "$TMP/bin/stat" <<'MOCK'
#!/usr/bin/env bash
# stat -c '%U' <path> -> return owner based on path.
for a in "$@"; do
  case "$a" in
    */apps/proj-*) echo "pd-$(basename "$a")" ;;
    */portico-deploy-runners/proj-*) echo "pd-$(basename "$a")" ;;
    *) echo "root" ;;
  esac
done
exit 0
MOCK
chmod +x "$TMP/bin/id" "$TMP/bin/useradd" "$TMP/bin/systemctl" "$TMP/bin/install" "$TMP/bin/stat"
export PATH="$TMP/bin:$PATH"

# --- Simulated host filesystem (the "disposable host") ---
HOST_ROOT="$TMP/host"
mkdir -p "$HOST_ROOT/opt/portico-deploy/apps"
mkdir -p "$HOST_ROOT/var/lib/portico-deploy-runners"
mkdir -p "$HOST_ROOT/var/lib/portico-deploy"
mkdir -p "$HOST_ROOT/etc/systemd/system"
mkdir -p "$HOST_ROOT/usr/local/libexec"

cp "$ROOT/scripts/portico-deploy-enroll.sh" "$HOST_ROOT/usr/local/libexec/"
cp "$ROOT/scripts/portico-deploy-app-add.sh" "$HOST_ROOT/usr/local/libexec/"
cp "$ROOT/scripts/portico-deploy-app-remove.sh" "$HOST_ROOT/usr/local/libexec/"
cp "$ROOT/scripts/portico-deploy-reconcile.sh" "$HOST_ROOT/usr/local/libexec/"
chmod 0755 "$HOST_ROOT/usr/local/libexec"/*.sh

HOST="admin@disposable-host"
REPO1="owner/private-app-a"
REPO2="owner/private-app-b"
STATE_FILE="$HOST_ROOT/var/lib/portico-deploy/state.json"

# --- 1. Enrol the host (once, reusable across repos) ---
echo '=== 1. Enrolling host ==='
if ! PD_ROOT="$HOST_ROOT" bash "$HOST_ROOT/usr/local/libexec/portico-deploy-enroll.sh" \
    "$HOST" "$STATE_FILE" > "$TMP/enroll.out" 2>&1; then
  fail "enrolment failed"
fi
grep -q 'ENROLL_OK' "$TMP/enroll.out" || fail "ENROLL_OK missing"
[[ -f "$STATE_FILE" ]] || fail "state file not created"

# --- 2. Add app A (repo1) ---
echo '=== 2. Adding app A (repo1) ==='
if ! PD_ROOT="$HOST_ROOT" bash "$HOST_ROOT/usr/local/libexec/portico-deploy-app-add.sh" \
    proj-a "$HOST" "$REPO1" public static production "$STATE_FILE" > "$TMP/appa.out" 2>&1; then
  echo "APPA OUT: $(cat "$TMP/appa.out")" >&2
  which install
  fail "app A add failed"
fi
grep -q 'APP_ADD_OK' "$TMP/appa.out" || fail "APP_ADD_OK missing for A"
[[ -d "$HOST_ROOT/opt/portico-deploy/apps/proj-a" ]] || fail "app A dir missing"
[[ -d "$HOST_ROOT/opt/portico-deploy/apps/proj-a/releases" ]] || fail "app A releases dir missing"

# --- 3. Add app B (repo2, different repo, same host) ---
echo '=== 3. Adding app B (repo2, different repo) ==='
if ! PD_ROOT="$HOST_ROOT" bash "$HOST_ROOT/usr/local/libexec/portico-deploy-app-add.sh" \
    proj-b "$HOST" "$REPO2" dist static staging "$STATE_FILE" > "$TMP/appb.out" 2>&1; then
  fail "app B add failed"
fi
grep -q 'APP_ADD_OK' "$TMP/appb.out" || fail "APP_ADD_OK missing for B"
[[ -d "$HOST_ROOT/opt/portico-deploy/apps/proj-b" ]] || fail "app B dir missing"
[[ "$HOST_ROOT/opt/portico-deploy/apps/proj-b" != "$HOST_ROOT/opt/portico-deploy/apps/proj-a"* ]] || fail "app B dir inside app A"

# --- 4. Idempotency: re-add app A, no changes ---
echo '=== 4. Idempotency check ==='
if ! PD_ROOT="$HOST_ROOT" bash "$HOST_ROOT/usr/local/libexec/portico-deploy-app-add.sh" \
    proj-a "$HOST" "$REPO1" public static production "$STATE_FILE" > "$TMP/appa2.out" 2>&1; then
  fail "re-add app A failed"
fi
grep -q 'already registered identically' "$TMP/appa2.out" || fail "idempotency message missing"

# --- 5. Remove app A (data preserved) ---
echo '=== 5. Removing app A (data preserved) ==='
if ! PD_ROOT="$HOST_ROOT" bash "$HOST_ROOT/usr/local/libexec/portico-deploy-app-remove.sh" \
    proj-a "$HOST" "$REPO1" "$STATE_FILE" > "$TMP/removea.out" 2>&1; then
  fail "app A remove failed"
fi
grep -q 'APP_REMOVE_OK' "$TMP/removea.out" || fail "APP_REMOVE_OK missing"
grep -q 'data preserved' "$TMP/removea.out" || fail "data preservation missing"
[[ -d "$HOST_ROOT/opt/portico-deploy/apps/proj-a" ]] || fail "app A data deleted (should be preserved)"
[[ -d "$HOST_ROOT/opt/portico-deploy/apps/proj-a/releases" ]] || fail "app A releases deleted (should be preserved)"

# --- 6. Reconcile: app B still consistent ---
echo '=== 6. Reconcile ==='
export PD_SKIP_OWNERSHIP_CHECK=1
if ! PD_ROOT="$HOST_ROOT" bash "$HOST_ROOT/usr/local/libexec/portico-deploy-reconcile.sh" \
    "$HOST" "$REPO2" "$STATE_FILE" > "$TMP/reconcile.out" 2>&1; then
  echo "RECONCILE OUT: $(cat "$TMP/reconcile.out")" >&2
  fail "reconcile failed"
fi
unset PD_SKIP_OWNERSHIP_CHECK
grep -q 'RECONCILE_OK' "$TMP/reconcile.out" || fail "reconcile OK missing"

# --- 7. Re-add app A (reversibility) ---
echo '=== 7. Re-adding app A (reversibility) ==='
if ! PD_ROOT="$HOST_ROOT" bash "$HOST_ROOT/usr/local/libexec/portico-deploy-app-add.sh" \
    proj-a "$HOST" "$REPO1" public static production "$STATE_FILE" > "$TMP/readda.out" 2>&1; then
  fail "re-add app A failed"
fi
grep -q 'APP_ADD_OK' "$TMP/readda.out" || fail "APP_ADD_OK missing for re-add"
[[ -d "$HOST_ROOT/opt/portico-deploy/apps/proj-a" ]] || fail "app A not restored"

# --- Evidence ---
echo '=== EVIDENCE ==='
echo "Host: $HOST"
echo "Repo1: $REPO1"
echo "Repo2: $REPO2"
echo "State: $STATE_FILE"
echo "Apps registered: $(python3 -c "import json; s=json.load(open('$STATE_FILE')); print(', '.join(s.get('apps',{})))")"
echo "Removed apps: $(python3 -c "import json; s=json.load(open('$STATE_FILE')); print(', '.join(a['project'] for a in s.get('removed_apps',[])))")"

echo 'PASS: M2 E2E (simulated) two isolated apps from different repos'
