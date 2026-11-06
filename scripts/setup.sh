#!/usr/bin/env bash
# Bootstrap a single PRIVATE app repo + one dedicated Linux runner.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO='' PROJECT='' HOST='' RUNNER_LABEL='' ASSET_DIR='public' MODE='plan'

usage() {
  cat <<'HELP'
Pórtico Deploy MVP, Linux x64.
bash scripts/setup.sh --repo OWNER/PRIVATE-APP --project app --host user@host [--asset-dir public] [--artifact-type static|python|nodejs|docker-compose] [--plan|--stage|--apply]
Default is --plan; --apply requires explicit project confirmation.
Preconditions: gh auth with admin on repo, SSH host key trusted, remote passwordless sudo only for one-time bootstrap.
HELP
}
ARTIFACT_TYPE='static'
ENROLL_HOST='no'
while (($#)); do
  case "$1" in
    --repo) REPO="${2:?missing repo}"; shift 2;;
    --project) PROJECT="${2:?missing project}"; shift 2;;
    --host) HOST="${2:?missing host}"; shift 2;;
    --asset-dir) ASSET_DIR="${2:?missing directory}"; shift 2;;
    --artifact-type) ARTIFACT_TYPE="${2:?missing artifact type}"; shift 2;;
    --plan) MODE='plan'; shift;;
    --stage) MODE='stage'; shift;;
    --apply) MODE='apply'; shift;;
    --enroll) ENROLL_HOST='yes'; MODE='enroll'; shift;;
    --app-add) MODE='app-add'; shift;;
    --app-remove) MODE='app-remove'; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 2;;
  esac
done

# Derive archive filename from artifact type
case "$ARTIFACT_TYPE" in
  static) ARCHIVE_NAME="artifact.tgz" ;;
  python) ARCHIVE_NAME="artifact.tgz" ;;
  nodejs) ARCHIVE_NAME="artifact.tgz" ;;
  docker-compose) echo "STOP: Docker/Compose packaging-only; deployment unsupported." >&2; exit 2 ;;
  *) echo "Unsupported artifact type: $ARTIFACT_TYPE" >&2; exit 2 ;;
esac

# Directories for adapter-specific artifact packaging
PD_APP_DIR="${APP_DIR:-${ASSET_DIR}}"
PD_BUILD_DIR="${BUILD_DIR:-${ASSET_DIR}}"
PD_COMPOSE_DIR="${COMPOSE_DIR:-${ASSET_DIR}}"

[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "Invalid repo" >&2; exit 2; }
[[ "$PROJECT" =~ ^[a-z][a-z0-9-]{1,20}$ ]] || { echo "Invalid project" >&2; exit 2; }
[[ "$HOST" =~ ^[A-Za-z0-9_][A-Za-z0-9_.@-]*$ ]] || { echo "Invalid host" >&2; exit 2; }
[[ "$ASSET_DIR" =~ ^[A-Za-z0-9][A-Za-z0-9_./-]*$ && "$ASSET_DIR" != /* && "/$ASSET_DIR/" != *"/../"* ]] || { echo "Invalid asset dir" >&2; exit 2; }
RUNNER_LABEL="pd-$PROJECT"
for cmd in gh ssh python3 curl base64 cmp; do
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
  echo 'PLAN ONLY. Nothing was changed. Use --stage to open a PR, merge the approved workflow, then --apply or --enroll or --app-add.'
  exit 0
fi

# M2: Mode-based execution (remote via SSH, confirmed explicitly, idempotent).
STATE_FILE='/var/lib/portico-deploy/state.json'
REMOTE_SCRIPTS_DIR='/usr/local/libexec'

deploy_remote_script() {
  # $1 = local script path, $2 = remote script name.
  local local_script="$1" remote_name="$2"
  [[ -f "$local_script" ]] || { echo "STOP: missing local script $local_script" >&2; exit 1; }
  ssh -o BatchMode=yes -o StrictHostKeyChecking=yes "$HOST" "sudo -n install -d -m 0755 $REMOTE_SCRIPTS_DIR" >/dev/null
  ssh -o BatchMode=yes "$HOST" "sudo -n tee $REMOTE_SCRIPTS_DIR/$remote_name >/dev/null && sudo -n chmod 0755 $REMOTE_SCRIPTS_DIR/$remote_name" < "$local_script"
}

if [[ "$MODE" == enroll ]]; then
  if ! gh repo view "$REPO" --quiet --affiliated 2>/dev/null; then
    echo "STOP: Repo not affiliated or accessible via GitHub" >&2
    exit 1
  fi
  printf 'Type ENROLL-%s to authorize host enrolment: ' "$PROJECT"
  read -r CONFIRM
  [[ "$CONFIRM" == "ENROLL-$PROJECT" ]] || { echo "Cancelled"; exit 1; }
  deploy_remote_script "$ROOT/scripts/portico-deploy-enroll.sh" portico-deploy-enroll.sh
  ssh -o BatchMode=yes -o StrictHostKeyChecking=yes "$HOST" "sudo -n $REMOTE_SCRIPTS_DIR/portico-deploy-enroll.sh '$HOST' '$REPO' '$STATE_FILE'" >&2
  echo "ENROLL_OK: host $HOST enrolled for repo $REPO (state: $STATE_FILE)."
  exit 0
fi

if [[ "$MODE" == app-add ]]; then
  printf 'Type ADD-%s to authorize app registration: ' "$PROJECT"
  read -r CONFIRM
  [[ "$CONFIRM" == "ADD-$PROJECT" ]] || { echo "Cancelled"; exit 1; }
  deploy_remote_script "$ROOT/scripts/portico-deploy-app-add.sh" portico-deploy-app-add.sh
  ssh -o BatchMode=yes -o StrictHostKeyChecking=yes "$HOST" "sudo -n $REMOTE_SCRIPTS_DIR/portico-deploy-app-add.sh '$PROJECT' '$HOST' '$REPO' '$ASSET_DIR' '$ARTIFACT_TYPE' '$STATE_FILE'" >&2
  echo "APP_ADD_OK: project $PROJECT registered on host $HOST."
  exit 0
fi

if [[ "$MODE" == app-remove ]]; then
  printf 'Type REMOVE-%s to authorize app removal (data preserved): ' "$PROJECT"
  read -r CONFIRM
  [[ "$CONFIRM" == "REMOVE-$PROJECT" ]] || { echo "Cancelled"; exit 1; }
  deploy_remote_script "$ROOT/scripts/portico-deploy-app-remove.sh" portico-deploy-app-remove.sh
  ssh -o BatchMode=yes -o StrictHostKeyChecking=yes "$HOST" "sudo -n $REMOTE_SCRIPTS_DIR/portico-deploy-app-remove.sh '$PROJECT' '$HOST' '$REPO' '$STATE_FILE'" >&2
  echo "APP_REMOVE_OK: project $PROJECT unregistered on host $HOST; data preserved."
  exit 0
fi
printf 'Type project name to authorize bootstrap: '
read -r CONFIRM
[[ "$CONFIRM" == "$PROJECT" ]] || { echo "Cancelled"; exit 1; }
BRANCH="$(gh repo view "$REPO" --json defaultBranchRef --jq .defaultBranchRef.name)"
[[ "$BRANCH" == main ]] || { echo "STOP: MVP requires main as default branch." >&2; exit 1; }
if ! gh api "repos/$REPO/branches/main/protection" >/dev/null 2>&1; then
  echo "STOP: main branch protection missing or inaccessible; fail closed." >&2
  exit 1
fi
echo 'Generating workflow in private app repository.'
TMP_WORKFLOW="$(mktemp)"
TMP_REMOTE="$(mktemp)"
trap 'rm -f "$TMP_WORKFLOW" "$TMP_REMOTE"' EXIT
PD_REPO="$REPO" PD_PROJECT="$PROJECT" PD_LABEL="$RUNNER_LABEL" PD_ASSET_DIR="$ASSET_DIR" PD_ARTIFACT_TYPE="$ARTIFACT_TYPE" PD_ARTIFACT_ARCHIVE="$ARCHIVE_NAME" PD_APP_DIR="$PD_APP_DIR" PD_BUILD_DIR="$PD_BUILD_DIR" PD_COMPOSE_DIR="$PD_COMPOSE_DIR" PD_SOURCE="$ROOT/templates/portico-deploy.yml" PD_DEST="$TMP_WORKFLOW" python3 - <<'PY'
import os
from pathlib import Path
x=Path(os.environ["PD_SOURCE"]).read_text()
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
}.items(): x=x.replace(a,b)
Path(os.environ["PD_DEST"]).write_text(x)
PY

if [[ "$MODE" == stage ]]; then
  if gh api "repos/$REPO/contents/.github/workflows/portico-deploy.yml" >/dev/null 2>&1; then
    echo 'STOP: workflow already exists on main. Review it before installation.' >&2; exit 1
  fi
  echo 'Creating workflow PR without touching a server.'
  MAIN_SHA="$(gh api "repos/$REPO/branches/main" --jq .commit.sha)"
  [[ "$MAIN_SHA" =~ ^[a-f0-9]{40}$ ]] || { echo 'Invalid GitHub main SHA' >&2; exit 1; }
  SETUP_BRANCH="portico-deploy-setup-$PROJECT"
  gh api --method POST "repos/$REPO/git/refs" -f "ref=refs/heads/$SETUP_BRANCH" -f "sha=$MAIN_SHA" >/dev/null
  ENCODED="$(base64 -w0 "$TMP_WORKFLOW")"
  gh api --method PUT "repos/$REPO/contents/.github/workflows/portico-deploy.yml" -f "branch=$SETUP_BRANCH" -f 'message=chore: add guarded Portico Deploy workflow' -f "content=$ENCODED" >/dev/null
  gh api --method POST "repos/$REPO/pulls" -f "base=main" -f "head=$SETUP_BRANCH" -f "title=chore: prepare Portico Deploy for $PROJECT" -f 'body=Review the workflow and merge to protected main. This PR does not deploy or register a runner.' --jq .html_url
  echo 'STAGED: no server touched. After review/merge, run --apply.'
  exit 0
fi
# Fail closed until the exact approved template is present on protected main.
if ! gh api "repos/$REPO/contents/.github/workflows/portico-deploy.yml" --jq .content | base64 -d > "$TMP_REMOTE"; then
  echo 'STOP: workflow unavailable on main. Run --stage and merge its PR first.' >&2; exit 1
fi
if ! cmp -s "$TMP_WORKFLOW" "$TMP_REMOTE"; then
  echo 'STOP: workflow differs from approved rendered template. Review/reconcile before installation.' >&2; exit 1
fi
echo 'Approved workflow confirmed on protected main; provisioning server.'
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes "$HOST" 'sudo -n true && command -v curl && command -v python3 && command -v tar && command -v sha256sum && command -v useradd && command -v systemctl' >/dev/null
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
ssh -o BatchMode=yes "$HOST" 'sudo -n tee /usr/local/libexec/portico-deploy-disable-runner.sh >/dev/null && sudo -n chmod 0755 /usr/local/libexec/portico-deploy-disable-runner.sh' < "$ROOT/scripts/disable-runner.sh"
ssh -o BatchMode=yes "$HOST" 'sudo -n tee /usr/local/libexec/portico-deploy-verify.sh >/dev/null && sudo -n chmod 0755 /usr/local/libexec/portico-deploy-verify.sh' < "$ROOT/scripts/verify-deploy.sh"
TOKEN="$(gh api --method POST "repos/$REPO/actions/runners/registration-token" --jq .token)"
if [[ -z "$TOKEN" ]]; then echo 'Unable to get token' >&2; exit 1; fi
# Token via stdin, never passed as process argument or persisted by bootstrap.
printf '%s\n' "$TOKEN" | ssh -o BatchMode=yes "$HOST" "sudo -n bash /usr/local/libexec/portico-deploy-provision.sh '$REPO' '$PROJECT' '$RUNNER_LABEL' '$RUNNER_URL' '$RUNNER_SHA'"
unset TOKEN

echo 'CONFIGURED: approved workflow verified and dedicated runner provisioned.'
echo 'Automatic deploy is disabled unless PD_AUTO_DEPLOY=true.'
echo "Next: review environment production; put static assets under '$ASSET_DIR'; invoke gh workflow run portico-deploy.yml -R '$REPO' --ref main."
