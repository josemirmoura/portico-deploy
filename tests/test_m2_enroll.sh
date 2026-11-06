#!/usr/bin/env bash
# M2: host enrolment (--enroll). Validates explicit confirmation, remote script
# copy, idempotency, and rejection of bad input. Uses mocked gh/ssh (no real host).
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
echo '{}' > "$REMOTE_STATE"

# --- Mock gh ---
cat > "$TMP/bin/gh" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1 $2" == "auth status" ]]; then exit 0; fi
if [[ "$1 $2" == "repo view" ]]; then
  if [[ " $* " == *" --affiliated "* ]]; then exit 0; fi
  echo true; exit 0
fi
echo "Unexpected gh: $*" >&2; exit 1
MOCK

# --- Mock ssh: simulates remote enrolment script with idempotency ---
# The remote command is passed as a single quoted string in $@.
# We detect enrolment invocations and use REMOTE_STATE for idempotency.
cat > "$TMP/bin/ssh" <<'MOCK'
#!/usr/bin/env bash
echo "SSH $*" >> "${SSH_EVENTS:?}"
if [[ " $* " == *" tee /usr/local/libexec/"* ]]; then exit 0; fi
if [[ " $* " == *"portico-deploy-enroll.sh "* ]]; then
  # The last argument is the remote command string.
  remote_cmd="${@: -1}"
  if [[ -f "$REMOTE_STATE" ]]; then
    echo "ENROLL_OK: host already enrolled (state: $remote_cmd); no changes."
  else
    echo '{}' > "$REMOTE_STATE"
    echo "ENROLL_OK: host enrolled (state: $remote_cmd)."
  fi
  exit 0
fi
exit 0
MOCK
chmod +x "$TMP/bin/"*

PROJECT="demo-site"
HOST="admin@test-host"
REPO="owner/private-app"

# 1. Wrong confirmation must cancel.
if printf 'WRONG\n' | PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo "$REPO" --project "$PROJECT" --host "$HOST" --enroll > "$TMP/out1" 2>&1; then
  fail "wrong confirmation accepted"
fi
grep -q 'Cancelled' "$TMP/out1" || fail "cancel message missing"

# 2. Correct confirmation enrols.
if ! printf 'ENROLL-%s\n' "$PROJECT" | PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo "$REPO" --project "$PROJECT" --host "$HOST" --enroll > "$TMP/out2" 2>&1; then
  fail "enrolment failed"
fi
grep -q 'ENROLL_OK' "$TMP/out2" || fail "ENROLL_OK missing in out2"
grep -q 'portico-deploy-enroll.sh' "$SSH_EVENTS" || fail "remote script not copied"
grep -q 'state.json' "$SSH_EVENTS" || fail "state file path not passed"

# 3. Idempotency: second enrolment same host/repo must report already enrolled.
if ! printf 'ENROLL-%s\n' "$PROJECT" | PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo "$REPO" --project "$PROJECT" --host "$HOST" --enroll > "$TMP/out3" 2>&1; then
  fail "second enrolment failed"
fi
grep -q 'already enrolled' "$TMP/out3" || fail "idempotency message missing"

echo 'PASS: M2 enrolment (confirmation, remote copy, idempotency)'
