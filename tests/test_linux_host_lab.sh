#!/usr/bin/env bash
# Runs only on GitHub-hosted ephemeral Ubuntu (real user accounts; no actual runner registration).
set -euo pipefail
[[ "$(id -u)" == 0 ]] || { echo 'root required for disposable lab' >&2; exit 1; }
[[ -f "${M1_ARCHIVE:?missing cross-job artifact}" ]] || exit 1
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d -p /tmp portico-m1-lab-XXXXXX)"
chmod 755 "$TMP"
USER_NAME="pdm1lab"
SERVER_PID=''
cleanup() {
  if [[ -n "$SERVER_PID" ]]; then kill "$SERVER_PID" 2>/dev/null || :; wait "$SERVER_PID" 2>/dev/null || :; fi
  userdel "$USER_NAME" 2>/dev/null || :
  rm -rf -- "$TMP"
}
trap cleanup EXIT
# Only create a dedicated disposable user on the GitHub-hosted VM.
if id "$USER_NAME" >/dev/null 2>&1; then echo "unexpected user collision" >&2; exit 1; fi
useradd --system --shell /usr/sbin/nologin "$USER_NAME"
mkdir -p "$TMP/apps/demo/releases" "$TMP/private"
chmod 0700 "$TMP/private"
printf 'forbidden\n' > "$TMP/private/secret.txt"
chown "$USER_NAME:$USER_NAME" "$TMP/apps/demo" "$TMP/apps/demo/releases"
chmod 0755 "$TMP/apps" "$TMP/apps/demo" "$TMP/apps/demo/releases"
install -m 0644 "$SRC/scripts/release.py" "$TMP/release.py"
install -m 0644 "$M1_ARCHIVE" "$TMP/v1.tgz"
mkdir "$TMP/v2"
printf 'portico-disposable-v2\n' > "$TMP/v2/index.html"
tar -czf "$TMP/v2.tgz" -C "$TMP/v2" .
chmod 0644 "$TMP/v2.tgz"
# Explicit access boundaries: runner user must not read unrelated secrets nor sudo.
if runuser -u "$USER_NAME" -- test -r "$TMP/private/secret.txt"; then echo 'cross-project secret exposed' >&2; exit 1; fi
if runuser -u "$USER_NAME" -- sudo -n true 2>/dev/null; then echo 'runner has sudo' >&2; exit 1; fi
if id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx docker; then echo 'runner in Docker group' >&2; exit 1; fi
# Use same Python release engine under an unprivileged real host identity.
runuser -u "$USER_NAME" -- python3 - "$TMP" <<'PY'
import importlib.util, pathlib, sys
base=pathlib.Path(sys.argv[1]); spec=importlib.util.spec_from_file_location("pd_release",base/"release.py")
pd=importlib.util.module_from_spec(spec);spec.loader.exec_module(pd)
pd.publish(base/"apps/demo","1"*40,base/"v1.tgz")
PY
runuser -u www-data -- test -r "$TMP/apps/demo/current/index.html" || { echo 'web user cannot read release' >&2; exit 1; }
# Local HTTP service is also unprivileged and serves current, never a privileged host service.
runuser -u www-data -- python3 -m http.server 18793 --bind 127.0.0.1 --directory "$TMP/apps/demo/current" > "$TMP/http.log" 2>&1 &
SERVER_PID=$!
for attempt in {1..30}; do
  if curl -fsS --max-time 1 http://127.0.0.1:18793/index.html | grep -qx 'portico-disposable-v1'; then break; fi
  sleep .2
done
curl -fsS --max-time 3 http://127.0.0.1:18793/index.html | grep -qx 'portico-disposable-v1'
runuser -u "$USER_NAME" -- python3 - "$TMP" <<'PY'
import importlib.util,pathlib,sys
base=pathlib.Path(sys.argv[1]);spec=importlib.util.spec_from_file_location("pd_release",base/"release.py")
pd=importlib.util.module_from_spec(spec);spec.loader.exec_module(pd)
pd.publish(base/"apps/demo","2"*40,base/"v2.tgz")
PY
curl -fsS --max-time 3 http://127.0.0.1:18793/index.html | grep -qx 'portico-disposable-v2'
runuser -u "$USER_NAME" -- python3 - "$TMP" <<'PY'
import importlib.util,pathlib,sys
base=pathlib.Path(sys.argv[1]);spec=importlib.util.spec_from_file_location("pd_release",base/"release.py")
pd=importlib.util.module_from_spec(spec);spec.loader.exec_module(pd)
assert pd.rollback(base/"apps/demo")=="releases/"+"1"*40
PY
curl -fsS --max-time 3 http://127.0.0.1:18793/index.html | grep -qx 'portico-disposable-v1'
test "$(grep -c '"action":' "$TMP/apps/demo/deploy-events.jsonl")" -eq 3
echo 'PASS M1_HOSTED_LAB real_user=true other_project_denied=true sudo_denied=true docker_denied=true cross_job_artifact=true http_v1_v2_rollback=true'
