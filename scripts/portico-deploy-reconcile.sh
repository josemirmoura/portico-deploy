#!/usr/bin/env bash
# Remote reconciliation (M2). Executed as root via SSH.
# Compares enrolment/app state against actual filesystem and reports drift.
# PD_ROOT overrides the filesystem root (used for tests/simulated hosts).
set -uo pipefail
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
[[ "$ENROLLED_HOST" == "$HOST" ]] || { echo 'RECONCILE_DRIFT: host mismatch with enrolment state' >&2; exit 1; }

# Base directories must exist.
for d in "${PD_ROOT}/opt/portico-deploy" "${PD_ROOT}/opt/portico-deploy/apps" "${PD_ROOT}/var/lib/portico-deploy-runners"; do
  if [[ ! -d "$d" ]]; then
    echo "RECONCILE_DRIFT: missing directory $d"
    DRIFT=1
  fi
done

# Every registered app must have its directory, runner user, and correct ownership.
# Use set +e around Python so a single missing dir does not abort the whole check.
set +e
python3 - "$STATE_FILE" "$PD_ROOT" <<'PY'
import json, sys, os, pwd
state_file, pd_root = sys.argv[1:3]
with open(state_file, encoding="utf-8") as f:
    state = json.load(f)
drift = 0
for project, info in state.get("apps", {}).items():
    app_dir = info.get("app_dir", f"{pd_root}/opt/portico-deploy/apps/{project}")
    runner_user = info.get("runner_user", f"pd-{project}")
    if not os.path.isdir(app_dir):
        print(f"RECONCILE_DRIFT: registered app {project} missing directory {app_dir}")
        drift = 1
    releases_dir = os.path.join(app_dir, "releases")
    if not os.path.isdir(releases_dir):
        print(f"RECONCILE_DRIFT: app {project} missing releases dir {releases_dir}")
        drift = 1
    # Ownership check is meaningful on real hosts; skip under PD_SKIP_OWNERSHIP_CHECK (tests).
    skip_owner = os.environ.get("PD_SKIP_OWNERSHIP_CHECK") == "1"
    if not skip_owner:
        try:
            st = os.stat(app_dir)
            owner = pwd.getpwuid(st.st_uid).pw_name
            if owner != runner_user:
                print(f"RECONCILE_DRIFT: app {project} dir {app_dir} owned by {owner}, expected {runner_user}")
                drift = 1
        except KeyError:
            print(f"RECONCILE_DRIFT: app {project} runner user {runner_user} does not exist on host")
            drift = 1
sys.exit(drift)
PY
PY_STATUS=$?
set -e
if [[ $PY_STATUS -ne 0 ]]; then
  DRIFT=1
fi

if [[ $DRIFT -eq 0 ]]; then
  echo "RECONCILE_OK: state matches filesystem for host $HOST."
else
  echo "RECONCILE_DRIFT: drift detected; operator reconciliation required." >&2
fi
exit $DRIFT
