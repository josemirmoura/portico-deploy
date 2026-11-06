#!/usr/bin/env bash
# Remote app registration (M2). Executed as root via SSH from setup.sh --app-add.
# Declarative, idempotent, isolated per project. No secrets persisted.
# A host enrolled once can register apps from DIFFERENT repositories.
# Each project gets a dedicated unprivileged user (pd-PROJECT) with segregated dirs.
# PD_ROOT overrides the filesystem root (used for tests/simulated hosts).
set -euo pipefail
[[ "$(id -u)" == 0 ]] || { echo 'Root required' >&2; exit 1; }
(( $# == 7 )) || { echo 'Usage: portico-deploy-app-add.sh PROJECT HOST REPO ASSET_DIR ARTIFACT_TYPE ENVIRONMENT STATE_FILE' >&2; exit 2; }
PROJECT="$1" HOST="$2" REPO="$3" ASSET_DIR="$4" ARTIFACT_TYPE="$5" ENVIRONMENT="$6" STATE_FILE="$7"
[[ "$PROJECT" =~ ^[a-z][a-z0-9-]{1,20}$ ]] || { echo 'Invalid project' >&2; exit 2; }
[[ "$HOST" =~ ^[A-Za-z0-9_][A-Za-z0-9_.@-]*$ ]] || { echo 'Invalid host' >&2; exit 2; }
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo 'Invalid repo' >&2; exit 2; }
[[ "$ASSET_DIR" =~ ^[A-Za-z0-9][A-Za-z0-9_./-]*$ && "$ASSET_DIR" != /* && "/$ASSET_DIR/" != *"/../"* ]] || { echo 'Invalid asset dir' >&2; exit 2; }
[[ "$ENVIRONMENT" =~ ^[a-z][a-z0-9-]{1,20}$ ]] || { echo 'Invalid environment' >&2; exit 2; }
case "$ARTIFACT_TYPE" in
  static|python|nodejs) ;;
  *) echo 'Unsupported artifact type' >&2; exit 2 ;;
esac

PD_ROOT="${PD_ROOT:-}"
STATE_DIR="$(dirname "$STATE_FILE")"
APP_DIR="${PD_ROOT}/opt/portico-deploy/apps/$PROJECT"
RUNNER_USER="pd-$PROJECT"
RUNNER_HOME="${PD_ROOT}/var/lib/portico-deploy-runners/$PROJECT"
RUNNER_LABEL="pd-$PROJECT"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Host must be enrolled first.
if [[ ! -f "$STATE_FILE" ]]; then
  echo "STOP: host not enrolled. Run setup.sh --enroll first." >&2
  exit 1
fi
ENROLLED_HOST="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("host",""))' "$STATE_FILE" 2>/dev/null || true)"
[[ "$ENROLLED_HOST" == "$HOST" ]] || { echo 'STOP: host mismatch with enrolment state' >&2; exit 1; }

# Idempotency: if app already registered with same config, no-op.
if python3 -c "import json,sys; s=json.load(open(sys.argv[1])); a=s.get('apps',{}).get(sys.argv[2],{}); sys.exit(0 if (a.get('project')==sys.argv[2] and a.get('host')==sys.argv[3] and a.get('repo')==sys.argv[4] and a.get('asset_dir')==sys.argv[5] and a.get('artifact_type')==sys.argv[6] and a.get('environment')==sys.argv[7]) else 1)" "$STATE_FILE" "$PROJECT" "$HOST" "$REPO" "$ASSET_DIR" "$ARTIFACT_TYPE" "$ENVIRONMENT" 2>/dev/null; then
  echo "APP_ADD_OK: project $PROJECT already registered identically; no changes."
  exit 0
fi

# Refuse if a directory for this project already exists with different content.
if [[ -e "$APP_DIR" && ! -d "$APP_DIR" ]]; then
  echo "STOP: $APP_DIR exists and is not a directory" >&2
  exit 1
fi

# Create dedicated unprivileged user for this project (no sudo, no docker group).
if id "$RUNNER_USER" >/dev/null 2>&1; then
  echo "APP_ADD_WARN: user $RUNNER_USER already exists; reusing."
else
  useradd --system --create-home --home-dir "$RUNNER_HOME" --shell /usr/sbin/nologin "$RUNNER_USER"
fi
id -nG "$RUNNER_USER" | tr ' ' '\n' | grep -qx docker && { echo 'STOP: runner user must not be in docker group' >&2; exit 1; }

# Create isolated project directory tree, owned by the project's runner user.
install -d -o "$RUNNER_USER" -g "$RUNNER_USER" -m 0755 "$APP_DIR"
install -d -o "$RUNNER_USER" -g "$RUNNER_USER" -m 0755 "$APP_DIR/releases"
install -d -o "$RUNNER_USER" -g "$RUNNER_USER" -m 0700 "$RUNNER_HOME"

# Update versioned state atomically (declarative, includes environment + repo).
python3 - "$STATE_FILE" "$PROJECT" "$HOST" "$REPO" "$ASSET_DIR" "$ARTIFACT_TYPE" "$ENVIRONMENT" "$RUNNER_LABEL" "$RUNNER_USER" "$APP_DIR" "$RUNNER_HOME" "$NOW" <<'PY'
import json, os, sys
(state_file, project, host, repo, asset_dir, artifact_type, environment,
 runner_label, runner_user, app_dir, runner_home, now) = sys.argv[1:13]
with open(state_file, encoding="utf-8") as f:
    state = json.load(f)
apps = state.setdefault("apps", {})
apps[project] = {
    "added_at": now,
    "host": host,
    "repo": repo,
    "project": project,
    "environment": environment,
    "asset_dir": asset_dir,
    "artifact_type": artifact_type,
    "runner_label": runner_label,
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

echo "APP_ADD_OK: project $PROJECT registered (repo=$REPO, env=$ENVIRONMENT, user=$RUNNER_USER, isolated at $APP_DIR)."
