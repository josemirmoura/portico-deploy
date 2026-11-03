#!/usr/bin/env bash
# Verify exact published HTTP revision. Failure always rolls back.
set -euo pipefail
(( $# == 3 )) || { echo 'Usage: verify-deploy.sh project sha HTTPS_BASE' >&2; exit 2; }
PROJECT="$1" SHA="$2" SITE_URL="$3"
[[ "$PROJECT" =~ ^[a-z][a-z0-9-]{1,20}$ ]] || exit 2
[[ "$SHA" =~ ^[a-f0-9]{40}$ ]] || exit 2
DEPLOY_CLI="${PORTICO_RELEASE_CLI:-/usr/local/libexec/portico-deploy-release.py}"
rollback() {
  echo "HTTP revision unverifiable; attempting rollback for $PROJECT" >&2
  /usr/bin/python3 "$DEPLOY_CLI" --project "$PROJECT" --rollback || {
    echo "CRITICAL: rollback failed; operator action required" >&2
    exit 3
  }
  exit 1
}
if [[ ! "$SITE_URL" =~ ^https://[a-zA-Z0-9][a-zA-Z0-9.-]*(/[a-zA-Z0-9._/-]*)?$ ]]; then
  echo 'PD_SITE_URL must be a reviewed public HTTPS base URL without query or port.' >&2
  rollback
fi
REMOTE_SHA="$(curl --proto '=https' --tlsv1.2 --fail --silent --show-error --max-time 8 --retry 3 --retry-delay 2 "${SITE_URL%/}/portico-deploy-revision.txt" || true)"
[[ "$REMOTE_SHA" == "$SHA" ]] || rollback
echo "DEPLOYED AND HTTP REVISION VERIFIED: $SHA"
