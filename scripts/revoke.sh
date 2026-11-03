#!/usr/bin/env bash
# Operator-side: GitHub runner removal token -> audited, narrow SSH command.
set -euo pipefail
REPO='' PROJECT='' HOST='' MODE='plan'
while (( $# )); do
  case "$1" in
    --repo) REPO="${2:?}"; shift 2;;
    --project) PROJECT="${2:?}"; shift 2;;
    --host) HOST="${2:?}"; shift 2;;
    --plan) MODE=plan; shift;;
    --apply) MODE=apply; shift;;
    *) echo "Usage: bash scripts/revoke.sh --repo owner/repo --project app --host user@host [--plan|--apply]" >&2; exit 2;;
  esac
done
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || exit 2
[[ "$PROJECT" =~ ^[a-z][a-z0-9-]{1,20}$ ]] || exit 2
[[ "$HOST" =~ ^[A-Za-z0-9_][A-Za-z0-9_.@-]*$ ]] || exit 2
echo "Plan: stop portico-deploy-$PROJECT.service, unregister $REPO runner, preserve project data and runner home."
[[ "$MODE" == apply ]] || exit 0
read -r -p "Type REVOKE-$PROJECT to authorize: " ANSWER
[[ "$ANSWER" == "REVOKE-$PROJECT" ]] || exit 1
command -v gh >/dev/null
gh auth status >/dev/null
# Runner identity and path checked by the root-owned disable-runner.sh.
TOKEN="$(gh api --method POST "repos/$REPO/actions/runners/remove-token" --jq .token)"
[[ "$TOKEN" =~ ^[A-Za-z0-9_-]{20,256}$ ]] || { echo 'Invalid token' >&2; exit 1; }
printf '%s\n' "$TOKEN" | ssh -o BatchMode=yes -o StrictHostKeyChecking=yes "$HOST" "sudo -n /bin/bash /usr/local/libexec/portico-deploy-disable-runner.sh '$REPO' '$PROJECT'"
unset TOKEN
