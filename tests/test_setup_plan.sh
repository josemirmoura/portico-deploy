#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1 $2" == "auth status" ]]; then exit 0; fi
if [[ "$1 $2" == "repo view" ]]; then
  [[ "${GH_TEST_PUBLIC:-0}" == 1 ]] && { echo false; exit; }
  echo true; exit
fi
echo 'Unexpected gh invocation' >&2; exit 1
MOCK
chmod +x "$TMP/bin/gh"
OUTPUT="$(PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo example/private-site --project demo-site --host admin@server --plan)"
grep -q 'PLAN ONLY' <<< "$OUTPUT"
if PATH="$TMP/bin:$PATH" GH_TEST_PUBLIC=1 bash "$ROOT/scripts/setup.sh" --repo example/public-site --project demo-site --host admin@server --plan >/dev/null 2>&1; then
  echo 'FAIL: public repository accepted' >&2; exit 1
fi
if PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo example/private-site --project '../escape' --host admin@server --plan >/dev/null 2>&1; then
  echo 'FAIL: path traversal project name accepted' >&2; exit 1
fi
if PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo example/private-site --project demo-site --host=-oProxyCommand=evil --plan >/dev/null 2>&1; then
  echo 'FAIL: ssh options injection accepted' >&2; exit 1
fi
echo 'PASS: dry-run and unsafe-input rejections'
