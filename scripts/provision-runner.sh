#!/usr/bin/env bash
# Trusted root-owned host bootstrap; must be invoked via explicit operator sudo.
set -euo pipefail
[[ "$(id -u)" == 0 ]] || { echo 'Root required' >&2; exit 1; }
(( $# == 5 )) || { echo 'Expected repo project label url checksum' >&2; exit 2; }
REPO="$1" PROJECT="$2" LABEL="$3" URL="$4" DIGEST="$5"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || exit 2
[[ "$PROJECT" =~ ^[a-z][a-z0-9-]{1,20}$ ]] || exit 2
[[ "$LABEL" == "pd-$PROJECT" ]] || exit 2
[[ "$URL" =~ ^https://github[.]com/actions/runner/releases/download/v[0-9.]+/actions-runner-linux-x64-[0-9.]+[.]tar[.]gz$ ]] || exit 2
[[ "$DIGEST" =~ ^[a-f0-9]{64}$ ]] || exit 2
IFS= read -r TOKEN
[[ "$TOKEN" =~ ^[A-Za-z0-9_-]{20,256}$ ]] || { echo 'Invalid registration token' >&2; exit 1; }
USER="pd-$PROJECT"
HOME_DIR="/var/lib/portico-deploy-runners/$PROJECT"
APP_DIR="/opt/portico-deploy/apps/$PROJECT"
if [[ -e "$HOME_DIR/.runner" || -e "$APP_DIR/current" ]]; then
  echo 'STOP: existing runner or deployment detected; refuse overwrite.' >&2
  exit 1
fi
if id "$USER" >/dev/null 2>&1; then
  echo 'STOP: runner user already exists; refuse account reuse.' >&2
  exit 1
fi
# Verify runner checksum before making persistent changes to the host.
DOWNLOAD="$(mktemp)"
trap 'rm -f "$DOWNLOAD"' EXIT
curl --fail --location --silent --show-error --retry 3 "$URL" -o "$DOWNLOAD"
printf '%s  %s\n' "$DIGEST" "$DOWNLOAD" | sha256sum --check --status || { echo 'Runner checksum mismatch' >&2; exit 1; }
install -d -m 0755 /var/lib/portico-deploy-runners
useradd --system --create-home --home-dir "$HOME_DIR" --shell /usr/sbin/nologin "$USER"
install -d -m 0755 /opt/portico-deploy /opt/portico-deploy/apps
install -d -o "$USER" -g "$USER" -m 0755 "$APP_DIR" "$APP_DIR/releases"
install -d -o "$USER" -g "$USER" -m 0700 "$HOME_DIR"
# Root reads the verified 0600 temp archive; unprivileged tar extracts through stdin.
cat "$DOWNLOAD" | runuser -u "$USER" -- tar -xzf - -C "$HOME_DIR"
cd "$HOME_DIR"
runuser -u "$USER" -- ./config.sh --unattended --url "https://github.com/$REPO" --token "$TOKEN" --name "$LABEL" --labels "$LABEL" --work _work
unset TOKEN
# Never execute runner-writable ./svc.sh as root: install a trusted systemd unit.
UNIT="portico-deploy-$PROJECT.service"
UNIT_PATH="/etc/systemd/system/$UNIT"
if [[ -e "$UNIT_PATH" ]]; then
  echo 'STOP: service unit already exists.' >&2; exit 1
fi
cat > "$UNIT_PATH" <<UNITFILE
[Unit]
Description=Portico Deploy isolated GitHub runner for $PROJECT
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$HOME_DIR
ExecStart=/bin/bash $HOME_DIR/run.sh
Restart=always
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$HOME_DIR $APP_DIR
RestrictSUIDSGID=true

[Install]
WantedBy=multi-user.target
UNITFILE
chmod 0644 "$UNIT_PATH"
systemctl daemon-reload
systemctl enable --now "$UNIT"
systemctl is-active --quiet "$UNIT" || { echo 'Runner service failed to start' >&2; exit 1; }
echo "Runner configured: $LABEL; app scope: $APP_DIR; unit: $UNIT"
