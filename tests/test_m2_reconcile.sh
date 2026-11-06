#!/usr/bin/env bash
# M2: reconcile (drift detection). Validates state vs filesystem consistency.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
export SSH_EVENTS="$TMP/ssh.events"
touch "$SSH_EVENTS"

cat > "$TMP/bin/id" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "-u" ]]; then echo 0; else echo "uid=0(root) gid=0(root) groups=0(root)"; fi
MOCK
chmod +x "$TMP/bin/id"

HOST="admin@test-host"
REPO="owner/private-app"

# Missing state file -> drift (exit 1).
if PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/portico-deploy-reconcile.sh" "$HOST" "$REPO" "$TMP/state.json" > "$TMP/out" 2>&1; then
  fail "reconcile should fail with missing state file"
fi
grep -q 'no enrolment state found' "$TMP/out" || fail "drift message missing"

# Create a fake state file and reconcile: OK (without mock ssh, script runs locally).
echo '{"version":1,"host":"admin@test-host","repo":"owner/private-app","apps":{}}' > "$TMP/state.json"
if ! PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/portico-deploy-reconcile.sh" "$HOST" "$REPO" "$TMP/state.json" > "$TMP/out2" 2>&1; then
  fail "reconcile failed"
fi
grep -q 'RECONCILE_OK' "$TMP/out2" || fail "reconcile OK missing"

echo 'PASS: M2 reconcile (drift detection)'
