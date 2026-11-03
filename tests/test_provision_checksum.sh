#!/usr/bin/env bash
# Root-only negative test in ephemeral GitHub-hosted runner: no account created on bad checksum.
set -euo pipefail
[[ "$(id -u)" == 0 ]] || { echo 'Requires root in ephemeral CI' >&2; exit 1; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'MOCK'
#!/usr/bin/env bash
out=''
while (( $# )); do
  if [[ "$1" == '-o' ]]; then out="$2"; shift 2; else shift; fi
done
[[ -n "$out" ]] || exit 10
printf 'invalid mocked runner bytes' > "$out"
MOCK
cat > "$TMP/bin/useradd" <<'MOCK'
#!/usr/bin/env bash
printf 'CALLED' > "${FAIL_MARKER:?}"
exit 1
MOCK
chmod +x "$TMP/bin/"*
export FAIL_MARKER="$TMP/useradd.called"
URL="https://github.com/actions/runner/releases/download/v2.338.2/actions-runner-linux-x64-2.338.2.tar.gz"
DIGEST="0000000000000000000000000000000000000000000000000000000000000000"
if printf '%s\n' 'syntheticregistrtoken1234567890' | PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/provision-runner.sh" example/private-site testsite pd-testsite "$URL" "$DIGEST" > "$TMP/out" 2>&1; then
  echo 'FAIL: accepted invalid checksum' >&2; exit 1
fi
[[ ! -e "$FAIL_MARKER" ]] || { echo 'FAIL: created account before validating archive' >&2; exit 1; }
echo 'PASS: bad checksum rejected before account creation'
