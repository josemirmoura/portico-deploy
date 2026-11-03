#!/usr/bin/env bash
# End-to-end installer orchestration with GitHub/SSH mocks; never connects to a real host.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
export PD_TEST_OUTPUT="$TMP/generated-workflow.yml"
export PD_TEST_SSH="$TMP/ssh-events"
cat > "$TMP/bin/gh" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1 ${2:-}" == 'auth status' ]]; then exit 0; fi
if [[ "$1 ${2:-}" == 'repo view' ]]; then
  if [[ " $* " == *" defaultBranchRef "* ]]; then echo main; else echo true; fi
  exit 0
fi
if [[ "$1 ${2:-}" == 'api repos/example/private-app/branches/main/protection' ]]; then
  echo '{}'; exit 0
fi
if [[ "$1 ${2:-}" == 'api repos/example/private-app/contents/.github/workflows/portico-deploy.yml' ]]; then
  exit 1
fi
if [[ "$1 ${2:-}" == 'api repos/actions/runner/releases/latest' ]]; then
  printf '%s\n' '{"assets":[{"name":"actions-runner-linux-x64-2.338.2.tar.gz","browser_download_url":"https://github.com/actions/runner/releases/download/v2.338.2/actions-runner-linux-x64-2.338.2.tar.gz","digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000"}]}'
  exit 0
fi
if [[ "$1 $2 $3" == 'api --method POST' ]]; then
  echo 'syntheticregistrtoken1234567890'; exit 0
fi
if [[ "$1 $2 $3" == 'api --method PUT' ]]; then
  if [[ "${GH_FAIL_WORKFLOW:-0}" == 1 ]]; then exit 1; fi
  for part in "$@"; do
    if [[ "$part" == content=* ]]; then
      printf '%s' "${part#content=}" | base64 -d > "${PD_TEST_OUTPUT:?}"
    fi
  done
  exit 0
fi
echo "Unexpected gh command: $*" >&2
exit 2
MOCK
cat > "$TMP/bin/ssh" <<'MOCK'
#!/usr/bin/env bash
echo 'ssh simulated' >> "${PD_TEST_SSH:?}"
cat >/dev/null
exit 0
MOCK
chmod +x "$TMP/bin/"*
printf '%s\n' demo-site | PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo example/private-app --project demo-site --host admin@remote --asset-dir dist --apply > "$TMP/result"
grep -q CONFIGURED "$TMP/result"
grep -q "example/private-app" "$PD_TEST_OUTPUT"
grep -q 'demo-site' "$PD_TEST_OUTPUT"
grep -q 'test -d "dist"' "$PD_TEST_OUTPUT"
[[ "$(wc -l < "$PD_TEST_SSH")" -ge 3 ]]
BEFORE="$(wc -l < "$PD_TEST_SSH")"
if printf '%s\n' demo-site | GH_FAIL_WORKFLOW=1 PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo example/private-app --project demo-site --host admin@remote --asset-dir dist --apply > "$TMP/failed" 2>&1; then
  echo 'FAIL: accepted GitHub workflow registration failure' >&2; exit 1
fi
[[ "$(wc -l < "$PD_TEST_SSH")" == "$BEFORE" ]] || { echo 'FAIL: contacted host before workflow was published' >&2; exit 1; }
echo 'PASS: setup pipeline simulated; GitHub failure cannot mutate host'
