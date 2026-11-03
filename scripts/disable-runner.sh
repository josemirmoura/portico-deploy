#!/usr/bin/env bash
# Revocation and safe deactivation: never delete applications, accounts or worktrees.
set -euo pipefail
[[ "$(id -u)" == 0 ]] || { echo "Root required" >&2; exit 1; }
(( $# == 2 )) || { echo "Usage: disable-runner.sh OWNER/REPO project (removal token via stdin)" >&2; exit 2; }
REPO="$1" PROJECT="$2"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || exit 2
[[ "$PROJECT" =~ ^[a-z][a-z0-9-]{1,20}$ ]] || exit 2
USER="pd-$PROJECT"
HOME_DIR="/var/lib/portico-deploy-runners/$PROJECT"
UNIT="portico-deploy-$PROJECT.service"
UNIT_PATH="/etc/systemd/system/$UNIT"
[[ -f "$UNIT_PATH" && ! -L "$UNIT_PATH" ]] || { echo "No managed unit found; no changes" >&2; exit 1; }
grep -Fxq "User=$USER" "$UNIT_PATH" || { echo "Unexpected unit identity" >&2; exit 1; }
grep -Fxq "WorkingDirectory=$HOME_DIR" "$UNIT_PATH" || { echo "Unexpected unit path" >&2; exit 1; }
IFS= read -r TOKEN
[[ "$TOKEN" =~ ^[A-Za-z0-9_-]{20,256}$ ]] || { echo "Invalid removal token" >&2; exit 1; }
# Stop first, so no new work can start even if remote unregister fails.
systemctl stop "$UNIT"
if [[ ! -x "$HOME_DIR/config.sh" ]]; then
  echo "Runner config missing. Service is stopped; manual reconciliation required." >&2
  exit 1
fi
cd "$HOME_DIR"
if ! runuser -u "$USER" -- ./config.sh remove --unattended --token "$TOKEN"; then
  echo "GitHub de-registration failed; runner remains stopped. Retry after repair." >&2
  exit 1
fi
systemctl disable "$UNIT"
rm -f -- "$UNIT_PATH"
systemctl daemon-reload
echo "RUNNER REVOKED: preserved $HOME_DIR, app data and service logs."
