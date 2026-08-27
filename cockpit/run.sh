#!/usr/bin/env bash
# Cockpit, on COCKPIT_HTTP_PORT/COCKPIT_HTTPS_PORT. Env vars: see README.

set -euo pipefail
command -v zz_use >/dev/null 2>&1 || { echo "zz_use not found on PATH - run this repo's setup.sh first: curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/setup.sh | sh" >&2; exit 1; }
zz_use "perspikapps/vps/common@${VPS_SETUP_REPO_REF:-main}"
# shellcheck disable=SC1091
. common

up() {
require_root
apt_update_once

COCKPIT_HTTP_PORT="${COCKPIT_HTTP_PORT:-$(net_port cockpit_http)}"
COCKPIT_HTTPS_PORT="${COCKPIT_HTTPS_PORT:-$(net_port cockpit_https)}"

zz_log i "[vps-setup] Installing Cockpit..."
apt_install cockpit cockpit-system cockpit-networkmanager cockpit-storaged

zz_log i "[vps-setup] Configuring cockpit.socket to listen on ${COCKPIT_HTTP_PORT} and ${COCKPIT_HTTPS_PORT}..."
mkdir -p /etc/systemd/system/cockpit.socket.d
cat > /etc/systemd/system/cockpit.socket.d/override.conf <<EOF
[Socket]
ListenStream=
ListenStream=${COCKPIT_HTTP_PORT}
ListenStream=${COCKPIT_HTTPS_PORT}
EOF

systemctl daemon-reload
systemctl enable --now cockpit.socket
systemctl restart cockpit.socket

ok "Cockpit installed. Reachable at https://<tailscale-ip>:${COCKPIT_HTTP_PORT} and :${COCKPIT_HTTPS_PORT} (self-signed cert)."
}

down() {
  require_root
  zz_log i "[vps-setup] Disabling Cockpit..."
  systemctl disable --now cockpit.socket 2>/dev/null || true
  rm -rf /etc/systemd/system/cockpit.socket.d
  systemctl daemon-reload
  zz_log i "[vps-setup] Removing Cockpit packages..."
  apt-get purge -y cockpit cockpit-system cockpit-networkmanager cockpit-storaged 2>/dev/null || true
  ok "Cockpit removed."
}

dispatch_action "$@"
