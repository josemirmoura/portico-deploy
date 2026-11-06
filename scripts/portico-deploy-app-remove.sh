#!/usr/bin/env bash
# Remote app removal (M2). Executed as root via SSH from setup.sh --app-remove.
# Reversible: stops service and removes config, but preserves app data (releases/current/previous)
# so the app can be re-added or restored without data loss.
# Verifies unit identity before removing any files.
# PD_ROOT overrides the filesystem root (used for tests/simulated hosts).
set -euo pipefail
[[ "$(id -u)" == 0 ]] || { echo 'Root required' >&2; exit 1; }
(( $# == 4 )) || { echo 'Usage: portico-deploy-app-remove.sh PROJECT HOST REPO STATE_FILE' >&2; exit 2; }
PROJECT="$1" HOST="$2" REPO="$3" STATE_FILE="$4"
[[ "$PROJECT" =~ ^[a-z][a-z0-9-]{1,20}$ ]] || { echo 'Invalid project' >&2; exit 2; }
[[ "$HOST" =~ ^[A-Za-z0-9_][A-Za-z0-9_.@-]*$ ]] || { echo 'Invalid host' >&2; exit 2; }
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo 'Invalid repo' >&2; exit 2; }

PD_ROOT="${PD_ROOT:-}"
APP_DIR="${PD_ROOT}/opt/portico-deploy/apps/$PROJECT"
RUNNER_USER="pd-$PROJECT"
UNIT="portico-deploy-$PROJECT.service"
UNIT_PATH="${PD_ROOT}/etc/systemd/system/$UNIT"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Host must be enrolled.
if [[ ! -f "$STATE_FILE" ]]; then
  echo "STOP: host not enrolled." >&2
  exit 1
fi
ENROLLED_HOST="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("host",""))' "$STATE_FILE" 2>/dev/null || true)"
[[ "$ENROLLED_HOST" == "$HOST" ]] || { echo 'STOP: host mismatch with enrolment state' >&2; exit 1; }

# App must be registered.
if ! python3 -c "import json,sys; sys.exit(0 if sys.argv[2] in json.load(open(sys.argv[1])).get('apps',{}) else 1)" "$STATE_FILE" "$PROJECT" 2>/dev/null; then
  echo "APP_REMOVE_OK: project $PROJECT not registered; nothing to remove."
  exit 0
fi

# Fail-closed: REPO passed must match the repo registered for this project.
REGISTERED_REPO="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("apps",{}).get(sys.argv[2],{}).get("repo",""))' "$STATE_FILE" "$PROJECT" 2>/dev/null || true)"
[[ "$REGISTERED_REPO" == "$REPO" ]] || { echo "STOP: repo $REPO does not match registered repo $REGISTERED_REPO for project $PROJECT; refuse removal." >&2; exit 1; }

# Verify unit identity before touching anything.
if [[ -f "$UNIT_PATH" ]]; then
  if ! grep -Fxq "User=$RUNNER_USER" "$UNIT_PATH"; then
    echo "STOP: unit $UNIT has unexpected identity (expected User=$RUNNER_USER)" >&2
    exit 1
  fi
  if ! grep -Fxq "WorkingDirectory=$APP_DIR" "$UNIT_PATH"; then
    echo "STOP: unit $UNIT has unexpected path (expected WorkingDirectory=$APP_DIR)" >&2
    exit 1
  fi
  # Stop first, so no new work can start. Fail closed if systemctl fails unexpectedly.
  if [[ "${PD_SKIP_SYSTEMD_CHECK:-}" != "1" ]]; then
    systemctl stop "$UNIT" || { echo "STOP: failed to stop unit $UNIT" >&2; exit 1; }
    systemctl disable "$UNIT" || { echo "STOP: failed to disable unit $UNIT" >&2; exit 1; }
    systemctl daemon-reload
  fi
  rm -f -- "$UNIT_PATH"
fi

# Remove app registration from state (reversible: data preserved on disk).
python3 - "$STATE_FILE" "$PROJECT" "$NOW" <<'PY'
import json, os, sys
(state_file, project, now) = sys.argv[1:4]
with open(state_file, encoding="utf-8") as f:
    state = json.load(f)
apps = state.get("apps", {})
if project in apps:
    removed = apps.pop(project)
    removed["removed_at"] = now
    state.setdefault("removed_apps", []).append(removed)
    tmp = state_file + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2, sort_keys=True)
        f.write("\n")
    os.chmod(tmp, 0o644)
    os.replace(tmp, state_file)
PY

echo "APP_REMOVE_OK: project $PROJECT unregistered; data preserved at $APP_DIR."
