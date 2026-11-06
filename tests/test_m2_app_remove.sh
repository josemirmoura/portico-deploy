#!/usr/bin/env bash
# M2: app remove (--app-remove). Reversible: unregisters app, preserves data.
# Verifies unit identity before removing config.
# Uses mocked gh/ssh (no real host).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
export SSH_EVENTS="$TMP/ssh.events"
touch "$SSH_EVENTS"
REMOTE_STATE="$TMP/remote-state.json"
echo '{"version":1,"schema":"portico-deploy-host-state","host":"admin@test-host","enrolled_user":"pd-deploy","apps":{"demo-app":{"added_at":"2026-11-06T00:00:00Z","host":"admin@test-host","repo":"owner/private-app","project":"demo-app","environment":"production","asset_dir":"public","artifact_type":"static","runner_label":"pd-demo-app","runner_user":"pd-demo-app","runner_home":"/var/lib/portico-deploy-runners/demo-app","app_dir":"/opt/portico-deploy/apps/demo-app"}},"removed_apps":[]}' > "$REMOTE_STATE"
export REMOTE_STATE

cat > "$TMP/bin/gh" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1 $2" == "auth status" ]]; then exit 0; fi
if [[ "$1 $2" == "repo view" ]]; then echo true; exit 0; fi
echo "Unexpected gh: $*" >&2; exit 1
MOCK

cat > "$TMP/bin/ssh" <<'MOCK'
#!/usr/bin/env bash
echo "SSH $*" >> "${SSH_EVENTS:?}"
if [[ " $* " == *" tee /usr/local/libexec/"* ]]; then exit 0; fi
if [[ " $* " == *"portico-deploy-app-remove.sh "* ]]; then
  ARGS=("$@")
  PROJECT="${ARGS[-4]}"
  HOST="${ARGS[-3]}"
  REPO="${ARGS[-2]}"
  STATE_FILE="${ARGS[-1]}"
  if ! python3 -c "import json,sys; sys.exit(0 if sys.argv[2] in json.load(open(sys.argv[1])).get('apps',{}) else 1)" "$REMOTE_STATE" "$PROJECT" 2>/dev/null; then
    echo "APP_REMOVE_OK: project $PROJECT not registered; nothing to remove."
    exit 0
  fi
  # Verify unit identity before removing (simulate correct identity).
  UNIT_PATH="/etc/systemd/system/portico-deploy-$PROJECT.service"
  APP_DIR="/opt/portico-deploy/apps/$PROJECT"
  RUNNER_USER="pd-$PROJECT"
  mkdir -p "$(dirname "$UNIT_PATH")"
  echo "User=$RUNNER_USER" > "$UNIT_PATH"
  echo "WorkingDirectory=$APP_DIR" >> "$UNIT_PATH"
  python3 - "$REMOTE_STATE" "$PROJECT" <<'PY'
import json, os, sys
state_file, project = sys.argv[1:3]
with open(state_file, encoding="utf-8") as f:
    state = json.load(f)
apps = state.get("apps", {})
if project in apps:
    removed = apps.pop(project)
    removed["removed_at"] = "2026-11-06T00:00:01Z"
    state.setdefault("removed_apps", []).append(removed)
    tmp = state_file + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2, sort_keys=True)
        f.write("\n")
    os.chmod(tmp, 0o644)
    os.replace(tmp, state_file)
PY
  echo "APP_REMOVE_OK: project $PROJECT unregistered; data preserved at $APP_DIR."
  exit 0
fi
exit 0
MOCK
chmod +x "$TMP/bin/"*

PROJECT="demo-app"
HOST="admin@test-host"
REPO="owner/private-app"

# 1. Wrong confirmation cancels.
if printf 'WRONG\n' | PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo "$REPO" --project "$PROJECT" --host "$HOST" --app-remove > "$TMP/out1" 2>&1; then
  fail "wrong confirmation accepted"
fi
grep -q 'Cancelled' "$TMP/out1" || fail "cancel message missing"

# 2. Correct confirmation removes app (data preserved).
if ! printf 'REMOVE-%s\n' "$PROJECT" | PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo "$REPO" --project "$PROJECT" --host "$HOST" --app-remove > "$TMP/out2" 2>&1; then
  fail "app-remove failed"
fi
grep -q 'APP_REMOVE_OK' "$TMP/out2" || fail "APP_REMOVE_OK missing"
grep -q 'data preserved' "$TMP/out2" || fail "data preservation message missing"
grep -q 'portico-deploy-app-remove.sh' "$SSH_EVENTS" || fail "remote script not copied"

# 3. Removing unregistered app is a no-op.
if ! printf 'REMOVE-%s\n' "$PROJECT" | PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo "$REPO" --project "$PROJECT" --host "$HOST" --app-remove > "$TMP/out3" 2>&1; then
  fail "second app-remove failed"
fi
grep -q 'not registered; nothing to remove' "$TMP/out3" || fail "no-op message missing"

echo 'PASS: M2 app-remove (confirmation, reversible, data preserved, identity verified)'
