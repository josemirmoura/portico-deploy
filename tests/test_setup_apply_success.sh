#!/usr/bin/env bash
# Integration simulation for stage (PR) and apply (verified approved workflow).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
export PD_TEST_OUTPUT="$TMP/approved-workflow.yml"
export PD_TEST_SSH="$TMP/ssh-events"
export PD_TEST_GH="$TMP/gh-events"
export PD_REPO=example/private-app
export PD_PROJECT=demo-site
export PD_LABEL=pd-demo-site
export PD_ASSET_DIR=dist
export PD_ARTIFACT_TYPE=static
export PD_ARTIFACT_ARCHIVE=site.tgz
export PD_APP_DIR=dist
export PD_BUILD_DIR=dist
export PD_COMPOSE_DIR=dist
PD_SOURCE="$ROOT/templates/portico-deploy.yml" PD_DEST="$PD_TEST_OUTPUT" python3 - <<'PY'
import os
from pathlib import Path
p=Path(os.environ["PD_SOURCE"]).read_text()
for a,b in {
    "@@REPO@@":os.environ["PD_REPO"],
    "@@PROJECT@@":os.environ["PD_PROJECT"],
    "@@RUNNER_LABEL@@":os.environ["PD_LABEL"],
    "@@ASSET_DIR@@":os.environ["PD_ASSET_DIR"],
    "@@ARTIFACT_TYPE@@":os.environ["PD_ARTIFACT_TYPE"],
    "@@ARTIFACT_ARCHIVE@@":os.environ["PD_ARTIFACT_ARCHIVE"],
    "@@APP_DIR@@":os.environ["PD_APP_DIR"],
    "@@BUILD_DIR@@":os.environ["PD_BUILD_DIR"],
    "@@COMPOSE_DIR@@":os.environ["PD_COMPOSE_DIR"],
}.items(): p=p.replace(a,b)
Path(os.environ["PD_DEST"]).write_text(p)
PY
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
  if [[ "${PD_TEST_STAGE:-0}" == 1 || "${PD_TEST_BAD:-0}" == 1 ]]; then
    if [[ "${PD_TEST_STAGE:-0}" == 1 ]]; then exit 1; fi
    printf 'dW5hcHByb3ZlZA=='; exit 0
  fi
  base64 -w0 "${PD_TEST_OUTPUT:?}"
  exit 0
fi
if [[ "$1 ${2:-}" == 'api repos/example/private-app/branches/main' ]]; then
  echo '1111111111111111111111111111111111111111'; exit 0
fi
if [[ "$1 ${2:-}" == 'api repos/actions/runner/releases/latest' ]]; then
  printf '%s\n' '{"assets":[{"name":"actions-runner-linux-x64-2.338.2.tar.gz","browser_download_url":"https://github.com/actions/runner/releases/download/v2.338.2/actions-runner-linux-x64-2.338.2.tar.gz","digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000"}]}'
  exit 0
fi
if [[ "$1 $2 $3" == 'api --method POST' ]]; then
  if [[ "$4" == *'/actions/runners/registration-token' ]]; then
    echo 'syntheticregistrtoken1234567890'; exit 0
  fi
  if [[ "$4" == *'/git/refs' || "$4" == *'/pulls' ]]; then
    echo "POST $4" >> "${PD_TEST_GH:?}"
    if [[ "$4" == *'/pulls' ]]; then echo 'https://github.com/example/private-app/pull/1'; fi
    exit 0
  fi
fi
if [[ "$1 $2 $3" == 'api --method PUT' ]]; then
  echo "PUT $4" >> "${PD_TEST_GH:?}"
  exit 0
fi
echo "Unexpected gh command: $*" >&2; exit 2
MOCK
cat > "$TMP/bin/ssh" <<'MOCK'
#!/usr/bin/env bash
echo 'ssh simulated' >> "${PD_TEST_SSH:?}"
cat >/dev/null
exit 0
MOCK
chmod +x "$TMP/bin/"*

# Stage creates PR via GitHub, but MUST NOT communicate with the destination.
printf '%s\n' demo-site | PD_TEST_STAGE=1 PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo example/private-app --project demo-site --host admin@remote --asset-dir dist --stage > "$TMP/staged"
grep -q STAGED "$TMP/staged"
grep -q 'POST repos/example/private-app/pulls' "$PD_TEST_GH"
[[ ! -e "$PD_TEST_SSH" ]] || { echo 'FAIL: stage contacted SSH host' >&2; exit 1; }

# Apply only after exact approved workflow exists.
printf '%s\n' demo-site | PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo example/private-app --project demo-site --host admin@remote --asset-dir dist --apply > "$TMP/result"
grep -q CONFIGURED "$TMP/result"
[[ "$(wc -l < "$PD_TEST_SSH")" -ge 3 ]]
BEFORE="$(wc -l < "$PD_TEST_SSH")"

# Tampered workflow on main must halt before any SSH call.
if printf '%s\n' demo-site | PD_TEST_BAD=1 PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo example/private-app --project demo-site --host admin@remote --asset-dir dist --apply > "$TMP/failed" 2>&1; then
  echo 'FAIL: accepted mismatched GitHub workflow' >&2; exit 1
fi
[[ "$(wc -l < "$PD_TEST_SSH")" == "$BEFORE" ]] || { echo 'FAIL: contacted host after template mismatch' >&2; exit 1; }
echo 'PASS: stage PR and apply reviewed workflow; unapproved changes cannot mutate host'
