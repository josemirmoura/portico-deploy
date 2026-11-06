#!/usr/bin/env bash
# M2: app add (--app-add). Declarative, idempotent, isolated per project.
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
export REMOTE_STATE
echo '{"version":1,"host":"admin@test-host","repo":"owner/private-app","apps":{}}' > "$REMOTE_STATE"

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
if [[ " $* " == *"portico-deploy-app-add.sh "* ]]; then
  remote_cmd="${@: -1}"
  if python3 -c "import json,sys; s=json.load(open(sys.argv[1])); a=s.get('apps',{}).get(sys.argv[2],{}); sys.exit(0 if (a.get('project')==sys.argv[2] and a.get('asset_dir')==sys.argv[3] and a.get('artifact_type')==sys.argv[4]) else 1)" "$REMOTE_STATE" "demo-app" "public" "static" 2>/dev/null; then
    echo "APP_ADD_OK: project demo-app already registered identically; no changes."
  else
    python3 - "$REMOTE_STATE" "demo-app" "admin@test-host" "owner/private-app" "public" "static" <<'PY'
import json, os, sys
state_file, project, host, repo, asset_dir, artifact_type = sys.argv[1:7]
with open(state_file, encoding="utf-8") as f:
    state = json.load(f)
state.setdefault("apps", {})[project] = {
    "added_at": "2026-11-06T00:00:00Z",
    "host": host,
    "repo": repo,
    "project": project,
    "asset_dir": asset_dir,
    "artifact_type": artifact_type,
    "runner_label": "pd-" + project,
    "app_dir": "/opt/portico-deploy/apps/" + project,
}
tmp = state_file + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(state, f, indent=2, sort_keys=True)
    f.write("\n")
os.chmod(tmp, 0o644)
os.replace(tmp, state_file)
PY
    echo "APP_ADD_OK: project demo-app registered (isolated at /opt/portico-deploy/apps/demo-app)."
  fi
  exit 0
fi
exit 0
MOCK
chmod +x "$TMP/bin/"*

PROJECT="demo-app"
HOST="admin@test-host"
REPO="owner/private-app"

# 1. Wrong confirmation cancels.
if printf 'WRONG\n' | PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo "$REPO" --project "$PROJECT" --host "$HOST" --app-add > "$TMP/out1" 2>&1; then
  fail "wrong confirmation accepted"
fi
grep -q 'Cancelled' "$TMP/out1" || fail "cancel message missing"

# 2. Correct confirmation registers app.
if ! printf 'ADD-%s\n' "$PROJECT" | PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo "$REPO" --project "$PROJECT" --host "$HOST" --asset-dir public --artifact-type static --app-add > "$TMP/out2" 2>&1; then
  fail "app-add failed"
fi
grep -q 'APP_ADD_OK' "$TMP/out2" || fail "APP_ADD_OK missing"
grep -q 'portico-deploy-app-add.sh' "$SSH_EVENTS" || fail "remote script not copied"

# 3. Idempotency: same config = no-op.
if ! printf 'ADD-%s\n' "$PROJECT" | PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo "$REPO" --project "$PROJECT" --host "$HOST" --asset-dir public --artifact-type static --app-add > "$TMP/out3" 2>&1; then
  fail "second app-add failed"
fi
grep -q 'already registered identically' "$TMP/out3" || fail "idempotency message missing"

echo 'PASS: M2 app-add (confirmation, declarative, idempotent, isolated)'
