#!/usr/bin/env bash
# M2: app add (--app-add). Declarative, idempotent, isolated per project.
# A host enrolled once can register apps from DIFFERENT repositories.
# Each project gets a dedicated unprivileged user (pd-PROJECT).
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
echo '{"version":1,"schema":"portico-deploy-host-state","host":"admin@test-host","enrolled_user":"pd-deploy","apps":{},"removed_apps":[]}' > "$REMOTE_STATE"

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
  ARGS=("$@")
  PROJECT="${ARGS[-7]}"
  HOST="${ARGS[-6]}"
  REPO="${ARGS[-5]}"
  ASSET_DIR="${ARGS[-4]}"
  ARTIFACT_TYPE="${ARGS[-3]}"
  ENVIRONMENT="${ARGS[-2]}"
  STATE_FILE="${ARGS[-1]}"
  if python3 -c "import json,sys; s=json.load(open(sys.argv[1])); a=s.get('apps',{}).get(sys.argv[2],{}); sys.exit(0 if (a.get('project')==sys.argv[2] and a.get('host')==sys.argv[3] and a.get('repo')==sys.argv[4] and a.get('asset_dir')==sys.argv[5] and a.get('artifact_type')==sys.argv[6] and a.get('environment')==sys.argv[7]) else 1)" "$REMOTE_STATE" "$PROJECT" "$HOST" "$REPO" "$ASSET_DIR" "$ARTIFACT_TYPE" "$ENVIRONMENT" 2>/dev/null; then
    echo "APP_ADD_OK: project $PROJECT already registered identically; no changes."
  else
    python3 - "$REMOTE_STATE" "$PROJECT" "$HOST" "$REPO" "$ASSET_DIR" "$ARTIFACT_TYPE" "$ENVIRONMENT" <<'PY'
import json, os, sys
state_file, project, host, repo, asset_dir, artifact_type, environment = sys.argv[1:8]
with open(state_file, encoding="utf-8") as f:
    state = json.load(f)
runner_user = "pd-" + project
runner_home = "/var/lib/portico-deploy-runners/" + project
app_dir = "/opt/portico-deploy/apps/" + project
state.setdefault("apps", {})[project] = {
    "added_at": "2026-11-06T00:00:00Z",
    "host": host,
    "repo": repo,
    "project": project,
    "environment": environment,
    "asset_dir": asset_dir,
    "artifact_type": artifact_type,
    "runner_label": "pd-" + project,
    "runner_user": runner_user,
    "runner_home": runner_home,
    "app_dir": app_dir,
}
tmp = state_file + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(state, f, indent=2, sort_keys=True)
    f.write("\n")
os.chmod(tmp, 0o644)
os.replace(tmp, state_file)
PY
    echo "APP_ADD_OK: project $PROJECT registered (repo=$REPO, env=$ENVIRONMENT, user=$runner_user, isolated at $app_dir)."
  fi
  exit 0
fi
exit 0
MOCK
chmod +x "$TMP/bin/"*

PROJECT="demo-app"
HOST="admin@test-host"
REPO1="owner/private-app"
REPO2="owner/other-private-app"

# 1. Wrong confirmation cancels.
if printf 'WRONG\n' | PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo "$REPO1" --project "$PROJECT" --host "$HOST" --asset-dir public --artifact-type static --environment production --app-add > "$TMP/out1" 2>&1; then
  fail "wrong confirmation accepted"
fi
grep -q 'Cancelled' "$TMP/out1" || fail "cancel message missing"

# 2. Correct confirmation registers app from repo1.
if ! printf 'ADD-%s\n' "$PROJECT" | PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo "$REPO1" --project "$PROJECT" --host "$HOST" --asset-dir public --artifact-type static --environment production --app-add > "$TMP/out2" 2>&1; then
  fail "app-add failed"
fi
grep -q 'APP_ADD_OK' "$TMP/out2" || fail "APP_ADD_OK missing"
grep -q 'portico-deploy-app-add.sh' "$SSH_EVENTS" || fail "remote script not copied"

# 3. Same host, different repo: app from repo2 can be registered (host reusable across repos).
PROJECT_B="demo-app-b"
if ! printf 'ADD-%s\n' "$PROJECT_B" | PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo "$REPO2" --project "$PROJECT_B" --host "$HOST" --asset-dir dist --artifact-type static --environment staging --app-add > "$TMP/out3" 2>&1; then
  fail "app-add from different repo failed"
fi
grep -q 'APP_ADD_OK' "$TMP/out3" || fail "APP_ADD_OK missing for repo2"
grep -q "repo=$REPO2" "$TMP/out3" || fail "repo2 not echoed"
grep -q "env=staging" "$TMP/out3" || fail "environment not echoed"

# 4. Idempotency: same config = no-op.
if ! printf 'ADD-%s\n' "$PROJECT" | PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo "$REPO1" --project "$PROJECT" --host "$HOST" --asset-dir public --artifact-type static --environment production --app-add > "$TMP/out4" 2>&1; then
  fail "second app-add failed"
fi
grep -q 'already registered identically' "$TMP/out4" || fail "idempotency message missing"

# 5. Negative: host not enrolled -> app-add rejected.
TMP2="$(mktemp -d)"
echo '{}' > "$TMP2/remote-state.json"
export REMOTE_STATE="$TMP2/remote-state.json"
cat > "$TMP/bin/ssh" <<'MOCK'
#!/usr/bin/env bash
echo "SSH $*" >> "${SSH_EVENTS:?}"
if [[ " $* " == *" tee /usr/local/libexec/"* ]]; then exit 0; fi
if [[ " $* " == *"portico-deploy-app-add.sh "* ]]; then
  # Simulate: host not enrolled -> reject (state file is {}).
  echo "STOP: host not enrolled. Run setup.sh --enroll first."
  exit 1
fi
exit 0
MOCK
chmod +x "$TMP/bin/ssh"
if printf 'ADD-%s\n' "$PROJECT" | PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo "$REPO1" --project "$PROJECT" --host "$HOST" --asset-dir public --artifact-type static --environment production --app-add > "$TMP2/out5" 2>&1; then
  fail "app-add on unenrolled host accepted"
fi
grep -q 'host not enrolled' "$TMP2/out5" || fail "unenrolled host rejection missing"
rm -rf "$TMP2"

echo 'PASS: M2 app-add (confirmation, declarative, idempotent, isolated, multi-repo, environment)'
