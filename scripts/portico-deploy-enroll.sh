#!/usr/bin/env bash
# Remote host enrolment (M2). Executed as root via SSH from setup.sh --enroll.
# Idempotent: second run is a no-op when host state already exists.
# A host can be enrolled ONCE and reused by apps from DIFFERENT repositories.
# PD_ROOT overrides the filesystem root (used for tests/simulated hosts).
set -euo pipefail
[[ "$(id -u)" == 0 ]] || { echo 'Root required' >&2; exit 1; }
(( $# == 2 )) || { echo 'Usage: portico-deploy-enroll.sh HOST STATE_FILE' >&2; exit 2; }
HOST="$1" STATE_FILE="$2"
[[ "$HOST" =~ ^[A-Za-z0-9_][A-Za-z0-9_.@-]*$ ]] || { echo 'Invalid host' >&2; exit 2; }

PD_ROOT="${PD_ROOT:-}"
STATE_DIR="$(dirname "$STATE_FILE")"
ENROLLED_USER="pd-deploy"
BASE_DIR="${PD_ROOT}/opt/portico-deploy"
RUNNER_ROOT="${PD_ROOT}/var/lib/portico-deploy-runners"
USER_HOME="${PD_ROOT}/var/lib/$ENROLLED_USER"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Idempotency: if host state exists with matching host, refuse re-enrolment.
if [[ -f "$STATE_FILE" ]]; then
  EXISTING_HOST="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("host",""))' "$STATE_FILE" 2>/dev/null || true)"
  if [[ "$EXISTING_HOST" == "$HOST" ]]; then
    echo "ENROLL_OK: host already enrolled (state: $STATE_FILE); no changes."
    exit 0
  fi
  echo "STOP: state file already exists for different host; refuse overwrite." >&2
  exit 1
fi

# Preconditions on the host.
command -v useradd >/dev/null || { echo 'STOP: useradd missing' >&2; exit 1; }
if [[ "${PD_SKIP_SYSTEMD_CHECK:-}" != "1" ]]; then
  command -v systemctl >/dev/null || { echo 'STOP: systemctl missing' >&2; exit 1; }
fi

# Create dedicated bootstrap user (no sudo, no docker group).
if id "$ENROLLED_USER" >/dev/null 2>&1; then
  echo "ENROLL_WARN: user $ENROLLED_USER already exists; reusing."
else
  useradd --system --create-home --home-dir "$USER_HOME" --shell /usr/sbin/nologin "$ENROLLED_USER"
fi
id -nG "$ENROLLED_USER" | tr ' ' '\n' | grep -qx docker && { echo 'STOP: enrolment user must not be in docker group' >&2; exit 1; }

# Base directories, owned by root, not writable by the enrolment user.
install -d -m 0755 "$BASE_DIR"
install -d -m 0755 "$BASE_DIR/apps"
install -d -m 0755 "$RUNNER_ROOT"
install -d -m 0755 "$STATE_DIR"

# Versioned enrolment state (no secrets). Host-centric: no single repo bound.
python3 - "$STATE_FILE" "$HOST" "$NOW" <<'PY'
import json, sys, os
state_file, host, now = sys.argv[1:4]
state = {
    "version": 1,
    "schema": "portico-deploy-host-state",
    "enrolled_at": now,
    "host": host,
    "enrolled_user": "pd-deploy",
    "apps": {},
    "removed_apps": [],
}
tmp = state_file + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(state, f, indent=2, sort_keys=True)
    f.write("\n")
os.chmod(tmp, 0o644)
os.replace(tmp, state_file)
PY

echo "ENROLL_OK: host $HOST enrolled (state: $STATE_FILE)."
