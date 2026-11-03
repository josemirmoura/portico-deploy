#!/usr/bin/env bash
# Real root-owned service/account setup and revocation in a disposable Ubuntu GitHub VM.
# The registration protocol is deliberately mocked, NOT a genuine GitHub registration.
set -euo pipefail
[[ "$(id -u)" == 0 ]] || { echo 'Requires ephemeral root' >&2; exit 1; }
trap 'echo "M1 lifecycle FAILED at line $LINENO" >&2' ERR
command -v systemctl >/dev/null
echo "systemd check: $(systemctl is-system-running 2>&1 || true)"
echo "PID1: $(ps -p 1 -o comm= || true)"
# A fresh ephemeral runner may temporarily report "starting"; actual unit tests decide acceptance.
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT=m1isolation
USER=pd-m1isolation
APP_DIR="/opt/portico-deploy/apps/$PROJECT"
HOME_DIR="/var/lib/portico-deploy-runners/$PROJECT"
UNIT="portico-deploy-$PROJECT.service"
UNIT_PATH="/etc/systemd/system/$UNIT"
[[ ! -e "$APP_DIR" && ! -e "$HOME_DIR" && ! -e "$UNIT_PATH" ]] || { echo 'Lab path already exists' >&2; exit 1; }
if id "$USER" >/dev/null 2>&1; then echo 'Test user exists' >&2; exit 1; fi
TMP="$(mktemp -d)"
cleanup() {
  systemctl stop "$UNIT" >/dev/null 2>&1 || :
  systemctl disable "$UNIT" >/dev/null 2>&1 || :
  rm -f -- "$UNIT_PATH"
  systemctl daemon-reload >/dev/null 2>&1 || :
  userdel "$USER" >/dev/null 2>&1 || :
  rm -rf -- "$HOME_DIR" "$APP_DIR" "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/fakerunner" "$TMP/bin"
cat > "$TMP/fakerunner/config.sh" <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
 --unattended) echo 'mock registered' > .runner ;;
 remove) rm -f .runner; echo 'mock unregistered' ;;
 *) exit 2;;
esac
RUNNER
cat > "$TMP/fakerunner/runsvc.sh" <<'RUNNER'
#!/usr/bin/env bash
exec sleep 600
RUNNER
chmod +x "$TMP/fakerunner/config.sh" "$TMP/fakerunner/runsvc.sh"
tar -czf "$TMP/runner-test.tar.gz" -C "$TMP/fakerunner" .
DIGEST="$(sha256sum "$TMP/runner-test.tar.gz" | cut -d' ' -f1)"
export MOCK_RUNNER_PACKAGE="$TMP/runner-test.tar.gz"
cat > "$TMP/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
OUT=''
while (( $# )); do
  if [[ "$1" == '-o' ]]; then OUT="$2"; shift 2; else shift; fi
done
[[ -n "$OUT" ]] || exit 2
cp -- "${MOCK_RUNNER_PACKAGE:?}" "$OUT"
MOCK
chmod +x "$TMP/bin/curl"
URL="https://github.com/actions/runner/releases/download/v2.338.2/actions-runner-linux-x64-2.338.2.tar.gz"
printf 'synthetic_registration_token_for_test_12345\n' |
  PATH="$TMP/bin:$PATH" bash "$SRC/scripts/provision-runner.sh" example/private-app "$PROJECT" "pd-$PROJECT" "$URL" "$DIGEST"
systemctl is-active --quiet "$UNIT"
systemctl is-enabled --quiet "$UNIT"
[[ -e "$HOME_DIR/.runner" ]]
[[ -f "$UNIT_PATH" ]]
grep -Fxq "ProtectSystem=strict" "$UNIT_PATH"
grep -Fxq "NoNewPrivileges=true" "$UNIT_PATH"
MAINPID="$(systemctl show -p MainPID --value "$UNIT")"
[[ "$MAINPID" =~ ^[1-9][0-9]*$ ]]
ACTUAL_USER="$(ps -o user= -p "$MAINPID" | xargs)"
[[ "$ACTUAL_USER" == "$USER" ]] || { echo 'Runner process has wrong user' >&2; exit 1; }
if runuser -u "$USER" -- sudo -n true 2>/dev/null; then echo 'runner has sudo' >&2; exit 1; fi
if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then echo 'runner in docker group' >&2; exit 1; fi
if runuser -u "$USER" -- test -w /etc; then echo 'runner can write /etc' >&2; exit 1; fi
# Keep an app file and prove deactivation never removes it.
runuser -u "$USER" -- sh -c "printf 'APP DATA\n' > '$APP_DIR/preserved.txt'"
printf 'synthetic_removal_token_for_test_12345678\n' |
  bash "$SRC/scripts/disable-runner.sh" example/private-app "$PROJECT"
[[ ! -e "$UNIT_PATH" ]]
[[ ! -e "$HOME_DIR/.runner" ]]
[[ -f "$HOME_DIR/config.sh" ]]
[[ -f "$APP_DIR/preserved.txt" ]]
[[ "$(cat "$APP_DIR/preserved.txt")" == 'APP DATA' ]]
[[ "$(systemctl is-active "$UNIT" 2>/dev/null || true)" != active ]]
echo 'PASS M1_RUNNER_LIFECYCLE real_linux_account=true systemd_nonroot=true restricted_service=true revoke=true data_preserved=true registration=mock'
