#!/usr/bin/env bash
# Remote reconciliation (M2). Executed as root via SSH.
# Compares enrolment/app state against actual filesystem and reports drift.
# PD_ROOT overrides the filesystem root (used for tests/simulated hosts).
set -euo pipefail
[[ "$(id -u)" == 0 ]] || { echo 'Root required' >&2; exit 1; }
(( $# == 3 )) || { echo 'Usage: portico-deploy-reconcile.sh HOST REPO STATE_FILE' >&2; exit 2; }
HOST="$1" REPO="$2" STATE_FILE="$3"
DRIFT=0

PD_ROOT="${PD_ROOT:-}"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "RECONCILE_DRIFT: no enrolment state found at $STATE_FILE"
  exit 1
fi

ENROLLED_HOST="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("host",""))' "$STATE_FILE" 2>/dev/null || true)"
ENROLLED_REPO="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("repo",""))' "$STATE_FILE" 2>/dev/null || true)"
[[ "$ENROLLED_HOST" == "$HOST" && "$ENROLLED_REPO" == "$REPO" ]] || { echo 'RECONCILE_DRIFT: host/repo mismatch' >&2; exit 1; }

# Base directories must exist.
for d in "${PD_ROOT}/opt/portico-deploy" "${PD_ROOT}/opt/portico-deploy/apps" "${PD_ROOT}/var/lib/portico-deploy-runners"; do
  if [[ ! -d "$d" ]]; then
    echo "RECONCILE_DRIFT: missing directory $d"
    DRIFT=1
  fi
done

# Every registered app must have its directory.
python3 - "$STATE_FILE" <<'PY'
import json, sys, os
state_file = sys.argv[1]
with open(state_file, encoding="utf-8") as f:
    state = json.load(f)
for project, info in state.get("apps", {}).items():
    app_dir = info.get("app_dir", f"/opt/portico-deploy/apps/{project}")
    if not os.path.isdir(app_dir):
        print(f"RECONCILE_DRIFT: registered app {project} missing directory {app_dir}")
        sys.exit(1)
PY
DRIFT=$?

if [[ $DRIFT -eq 0 ]]; then
  echo "RECONCILE_OK: state matches filesystem for host $HOST / repo $REPO."
else
  echo "RECONCILE_DRIFT: drift detected; operator reconciliation required." >&2
fi
exit $DRIFT
