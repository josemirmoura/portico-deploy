#!/usr/bin/env bash
# Bootstrap a single PRIVATE app repo + one dedicated Linux runner.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO='' PROJECT='' HOST='' RUNNER_LABEL='' ASSET_DIR='public' MODE='plan'

usage() {
  cat <<'HELP'
Pórtico Deploy MVP, Linux x64.
bash scripts/setup.sh --repo OWNER/PRIVATE-APP --project app --host user@host [--asset-dir public] [--plan|--apply]
Default is --plan; --apply requires explicit project confirmation.
Preconditions: gh auth with admin on repo, SSH host key trusted, remote passwordless sudo only for one-time bootstrap.
HELP
}
while (($#)); do
  case "$1" in
    --repo) REPO="${2:?missing repo}"; shift 2;;
    --project) PROJECT="${2:?missing project}"; shift 2;;
    --host) HOST="${2:?missing host}"; shift 2;;
    --asset-dir) ASSET_DIR="${2:?missing directory}"; shift 2;;
    --plan) MODE='plan'; shift;;
    --apply) MODE='apply'; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 2;;
  esac
done

[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "Invalid repo" >&2; exit 2; }
[[ "$PROJECT" =~ ^[a-z][a-z0-9-]{1,20}$ ]] || { echo "Invalid project" >&2; exit 2; }
[[ "$HOST" =~ ^[A-Za-z0-9_][A-Za-z0-9_.@-]*$ ]] || { echo "Invalid host" >&2; exit 2; }
[[ "$ASSET_DIR" =~ ^[A-Za-z0-9][A-Za-z0-9_./-]*$ && "$ASSET_DIR" != /* && "/$ASSET_DIR/" != *"/../"* ]] || { echo "Invalid asset dir" >&2; exit 2; }
RUNNER_LABEL="pd-$PROJECT"
for cmd in gh ssh python3 curl base64; do
  command -v "$cmd" >/dev/null || { echo "Missing $cmd" >&2; exit 1; }
done
gh auth status >/dev/null
PRIVACY="$(gh repo view "$REPO" --json isPrivate --jq .isPrivate)"
[[ "$PRIVACY" == true ]] || { echo "STOP: runner install only allowed for PRIVATE app repos" >&2; exit 1; }
printf 'Target repo: %s (private)\nHost: %s\nProject: %s\nRunner label: %s\nArtifact directory: %s\n' "$REPO" "$HOST" "$PROJECT" "$RUNNER_LABEL" "$ASSET_DIR"
echo "Target path: /opt/portico-deploy/apps/$PROJECT"
echo 'Bootstrap will create a dedicated unprivileged account, a runner service and a workflow in the app repo.'
echo 'It will not change reverse proxy, TLS, DNS, Docker or existing projects.'
if [[ "$MODE" == plan ]]; then
  echo 'PLAN ONLY. Nothing was changed. Rerun with --apply after reviewing docs/SECURITY.md.'
  exit 0
fi
printf 'Type project name to authorize bootstrap: '
read -r CONFIRM
[[ "$CONFIRM" == "$PROJECT" ]] || { echo "Cancelled"; exit 1; }
if gh api "repos/$REPO/contents/.github/workflows/portico-deploy.yml" >/dev/null 2>&1; then
  echo 'STOP: workflow already exists. Review manually; bootstrap never overwrites it.' >&2; exit 1
fi
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes "$HOST" 'sudo -n true && command -v curl && command -v python3 && command -v tar' >/dev/null
RUNNER_INFO="$(gh api repos/actions/runner/releases/latest | python3 -c '
import json,re,sys
x=json.load(sys.stdin)
p=re.compile(r"^actions-runner-linux-x64-[0-9]+[.][0-9]+[.][0-9]+[.]tar[.]gz$")
for a in x.get("assets",[]):
    if p.fullmatch(a.get("name","")):
        digest=a.get("digest") or ""
        if not re.fullmatch(r"sha256:[a-fA-F0-9]{64}",digest):
            sys.exit("Runner checksum unavailable; fail closed")
        print(a["browser_download_url"])
        print(digest.split(":",1)[1].lower())
        break
else:
    sys.exit("Unable to locate verified Linux x64 runner")
')"
mapfile -t RUNNER_FIELDS <<< "$RUNNER_INFO"
RUNNER_URL="${RUNNER_FIELDS[0]}"
RUNNER_SHA="${RUNNER_FIELDS[1]}"
echo 'Installing root-owned deploy code on selected host.'
ssh -o BatchMode=yes "$HOST" 'sudo -n install -d -m 0755 /usr/local/libexec'
ssh -o BatchMode=yes "$HOST" 'sudo -n tee /usr/local/libexec/portico-deploy-release.py >/dev/null && sudo -n chmod 0755 /usr/local/libexec/portico-deploy-release.py' < "$ROOT/scripts/release.py"
ssh -o BatchMode=yes "$HOST" 'sudo -n tee /usr/local/libexec/portico-deploy-provision.sh >/dev/null && sudo -n chmod 0755 /usr/local/libexec/portico-deploy-provision.sh' < "$ROOT/scripts/provision-runner.sh"
TOKEN="$(gh api --method POST "repos/$REPO/actions/runners/registration-token" --jq .token)"
if [[ -z "$TOKEN" ]]; then echo 'Unable to get token' >&2; exit 1; fi
# Token via stdin, never passed as process argument or persisted by bootstrap.
printf '%s\n' "$TOKEN" | ssh -o BatchMode=yes "$HOST" "sudo -n bash /usr/local/libexec/portico-deploy-provision.sh '$REPO' '$PROJECT' '$RUNNER_LABEL' '$RUNNER_URL' '$RUNNER_SHA'"
unset TOKEN
echo 'Generating workflow in private app repository.'
TMP_WORKFLOW="$(mktemp)"
trap 'rm -f "$TMP_WORKFLOW"' EXIT
PD_REPO="$REPO" PD_PROJECT="$PROJECT" PD_LABEL="$RUNNER_LABEL" PD_ASSET_DIR="$ASSET_DIR" PD_SOURCE="$ROOT/templates/portico-deploy.yml" PD_DEST="$TMP_WORKFLOW" python3 - <<'PY'
import os
from pathlib import Path
x=Path(os.environ["PD_SOURCE"]).read_text()
for a,b in {
 "@@REPO@@":os.environ["PD_REPO"],"@@PROJECT@@":os.environ["PD_PROJECT"],
 "@@RUNNER_LABEL@@":os.environ["PD_LABEL"],"@@ASSET_DIR@@":os.environ["PD_ASSET_DIR"],
}.items(): x=x.replace(a,b)
Path(os.environ["PD_DEST"]).write_text(x)
PY
ENCODED="$(base64 -w0 "$TMP_WORKFLOW")"
gh api --method PUT "repos/$REPO/contents/.github/workflows/portico-deploy.yml" -f 'message=chore: configure Portico Deploy manual workflow' -f "content=$ENCODED" >/dev/null
echo 'CONFIGURED: workflow_dispatch enabled. Automatic deploy disabled unless PD_AUTO_DEPLOY=true.'
echo "Next: protect main & environment production; put static assets under '$ASSET_DIR'; invoke gh workflow run portico-deploy.yml -R '$REPO' --ref main."
