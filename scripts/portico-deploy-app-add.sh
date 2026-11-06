#!/usr/bin/env bash
# Remote app registration (M2). Executed as root via SSH from setup.sh --app-add.
# Declarative, idempotent, isolated per project. No secrets persisted.
# PD_ROOT overrides the filesystem root (used for tests/simulated hosts).
set -euo pipefail
[[ "$(id -u)" == 0 ]] || { echo 'Root required' >&2; exit 1; }
(( $# == 6 )) || { echo 'Usage: portico-deploy-app-add.sh PROJECT HOST REPO ASSET_DIR ARTIFACT_TYPE STATE_FILE' >&2; exit 2; }
PROJECT="$1" HOST="$2" REPO="$3" ASSET_DIR="$4" ARTIFACT_TYPE="$5" STATE_FILE="$6"
[[ "$PROJECT" =~ ^[a-z][a-z0-9-]{1,20}$ ]] || { echo 'Invalid project' >&2; exit 2; }
[[ "$HOST" =~ ^[A-Za-z0-9_][A-Za-z0-9_.@-]*$ ]] || { echo 'Invalid host' >&2; exit 2; }
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo 'Invalid repo' >&2; exit 2; }
[[ "$ASSET_DIR" =~ ^[A-Za-z0-9][A-Za-z0-9_./-]*$ && "$ASSET_DIR" != /* && "/$ASSET_DIR/" != *"/../"* ]] || { echo 'Invalid asset dir' >&2; exit 2; }
case "$ARTIFACT_TYPE" in
  static|python|nodejs) ;;
  *) echo 'Unsupported artifact type' >&2; exit 2 ;;
esac

PD_ROOT="${PD_ROOT:-}"
STATE_DIR="$(dirname "$STATE_FILE")"
APP_DIR="${PD_ROOT}/opt/portico-deploy/apps/$PROJECT"
RUNNER_LABEL="pd-$PROJECT"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Host must be enrolled first.
if [[ ! -f "$STATE_FILE" ]]; then
  echo "STOP: host not enrolled. Run setup.sh --enroll first." >&2
  exit 1
fi
ENROLLED_HOST="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("host",""))' "$STATE_FILE" 2>/dev/null || true)"
ENROLLED_REPO="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("repo",""))' "$STATE_FILE" 2>/dev/null || true)"
[[ "$ENROLLED_HOST" == "$HOST" && "$ENROLLED_REPO" == "$REPO" ]] || { echo 'STOP: host/repo mismatch with enrolment state' >&2; exit 1; }

# Idempotency: if app already registered with same config, no-op.
if python3 -c "import json,sys; s=json.load(open(sys.argv[1])); a=s.get('apps',{}).get(sys.argv[2],{}); sys.exit(0 if (a.get('project')==sys.argv[2] and a.get('host')==sys.argv[3] and a.get('asset_dir')==sys.argv[4] and a.get('artifact_type')==sys.argv[5]) else 1)" "$STATE_FILE" "$PROJECT" "$HOST" "$ASSET_DIR" "$ARTIFACT_TYPE" 2>/dev/null; then
  echo "APP_ADD_OK: project $PROJECT already registered identically; no changes."
  exit 0
fi

# Refuse if a directory for this project already exists with different content.
if [[ -e "$APP_DIR" && ! -d "$APP_DIR" ]]; then
  echo "STOP: $APP_DIR exists and is not a directory" >&2
  exit 1
fi

# Create isolated project directory, owned by root (deploy code is root-owned).
install -d -m 0755 "$APP_DIR"
install -d -m 0755 "$APP_DIR/releases"

# Update versioned state atomically.
python3 - "$STATE_FILE" "$PROJECT" "$HOST" "$REPO" "$ASSET_DIR" "$ARTIFACT_TYPE" "$RUNNER_LABEL" "$APP_DIR" "$NOW" <<'PY'
import json, os, sys
(state_file, project, host, repo, asset_dir, artifact_type, runner_label, app_dir, now) = sys.argv[1:10]
with open(state_file, encoding="utf-8") as f:
    state = json.load(f)
apps = state.setdefault("apps", {})
apps[project] = {
    "added_at": now,
    "host": host,
    "repo": repo,
    "project": project,
    "asset_dir": asset_dir,
    "artifact_type": artifact_type,
    "runner_label": runner_label,
    "app_dir": app_dir,
}
tmp = state_file + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(state, f, indent=2, sort_keys=True)
    f.write("\n")
os.chmod(tmp, 0o644)
os.replace(tmp, state_file)
PY

echo "APP_ADD_OK: project $PROJECT registered (isolated at $APP_DIR)."
