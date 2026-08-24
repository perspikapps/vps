#!/usr/bin/env bash
# Install Cockpit and serve it on both COCKPIT_HTTP_PORT and
# COCKPIT_HTTPS_PORT (default 9080/9083) instead of the default 9090.
# Cockpit's web server (cockpit-ws) is TLS-only regardless of which port
# it's bound to; we just socket-activate it on two ports for convenience.
#
# Env vars:
#   COCKPIT_HTTP_PORT   - default from ../network.yaml (cockpit_http)
#   COCKPIT_HTTPS_PORT  - default from ../network.yaml (cockpit_https)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

up() {
require_root
apt_update_once

COCKPIT_HTTP_PORT="${COCKPIT_HTTP_PORT:-$(net_port cockpit_http)}"
COCKPIT_HTTPS_PORT="${COCKPIT_HTTPS_PORT:-$(net_port cockpit_https)}"

log "Installing Cockpit..."
apt_install cockpit cockpit-system cockpit-networkmanager cockpit-storaged

log "Configuring cockpit.socket to listen on ${COCKPIT_HTTP_PORT} and ${COCKPIT_HTTPS_PORT}..."
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
  log "Disabling Cockpit..."
  systemctl disable --now cockpit.socket 2>/dev/null || true
  rm -rf /etc/systemd/system/cockpit.socket.d
  systemctl daemon-reload
  log "Removing Cockpit packages..."
  apt-get purge -y cockpit cockpit-system cockpit-networkmanager cockpit-storaged 2>/dev/null || true
  ok "Cockpit removed."
}

dispatch_action "$@"
