#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
SHA="$(printf '%040d' 9)"
printf '%s\n' "$SHA" > "$TMP/response"
cat > "$TMP/bin/curl" <<'MOCK'
#!/usr/bin/env bash
cat "${HTTP_RESPONSE:?}"
MOCK
chmod +x "$TMP/bin/curl"
# Python CLI spy is a real Python program, returning 0 on rollback.
cat > "$TMP/release-spy.py" <<'PY'
import os
from pathlib import Path
import sys
assert "--rollback" in sys.argv
Path(os.environ["ROLLBACK_EVIDENCE"]).write_text("ROLLBACK")
PY
export HTTP_RESPONSE="$TMP/response"
export ROLLBACK_EVIDENCE="$TMP/rollback"
export PORTICO_RELEASE_CLI="$TMP/release-spy.py"
PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/verify-deploy.sh" sample "$SHA" https://example.org/site > "$TMP/pass"
grep -q 'HTTP REVISION VERIFIED' "$TMP/pass"
[[ ! -f "$ROLLBACK_EVIDENCE" ]] || exit 1
printf 'stale-old-version\n' > "$HTTP_RESPONSE"
if PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/verify-deploy.sh" sample "$SHA" https://example.org/site > "$TMP/failed" 2>&1; then
  echo 'FAIL: stale 200 succeeded' >&2; exit 1
fi
grep -qx 'ROLLBACK' "$ROLLBACK_EVIDENCE"
rm "$ROLLBACK_EVIDENCE"
if PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/verify-deploy.sh" sample "$SHA" '' > "$TMP/no-url" 2>&1; then
  echo 'FAIL: empty URL succeeded' >&2; exit 1
fi
grep -qx 'ROLLBACK' "$ROLLBACK_EVIDENCE"
echo 'PASS: exact SHA health succeeds, stale 200 and missing HTTPS URL trigger rollback'
