#!/usr/bin/env bash
# Cockpit, on COCKPIT_HTTP_PORT/COCKPIT_HTTPS_PORT. Env vars: see README.

set -euo pipefail
zz-use "perspikapps/vps/vps-common@${ZZ_SETUP_REF:-main}"
# shellcheck disable=SC1091
. vps-common

up() {
apt_update_once

COCKPIT_HTTP_PORT="$(net_port cockpit_http)"
COCKPIT_HTTPS_PORT="$(net_port cockpit_https)"

zz-log i "[vps-setup] Installing Cockpit..."
apt_install cockpit cockpit-system cockpit-networkmanager cockpit-storaged cockpit-packagekit cockpit-files

zz-log i "[vps-setup] Configuring cockpit.socket to listen on ${COCKPIT_HTTP_PORT} and ${COCKPIT_HTTPS_PORT}..."
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

ok "Cockpit installed. Reachable at https://$(summary_host):${COCKPIT_HTTP_PORT} and :${COCKPIT_HTTPS_PORT} (self-signed cert)."
}

down() {
  zz-log i "[vps-setup] Disabling Cockpit..."
  systemctl disable --now cockpit.socket 2>/dev/null || true
  rm -rf /etc/systemd/system/cockpit.socket.d
  systemctl daemon-reload
  zz-log i "[vps-setup] Removing Cockpit packages..."
  apt_purge cockpit cockpit-system cockpit-networkmanager cockpit-storaged cockpit-packagekit cockpit-files || true
  ok "Cockpit removed."
}

summary() {
  local host
  host="$(summary_host)"
  cat <<EOF
 Cockpit:             https://${host}:$(net_port cockpit_http)
                       https://${host}:$(net_port cockpit_https)
                       user:     $(vps_secret COCKPIT_ADMIN_USER /root/.cockpit-admin-user | grep . || echo 'not set - run vps-security/run.sh')
                       password: $(vps_secret COCKPIT_ADMIN_PASSWORD /root/.cockpit-admin-password | grep . || echo 'not set - run vps-security/run.sh')
                       (saved to ${VPS_SECRETS_FILE}; PAM login, same
                       account you'd use on the local console - separate
                       from SSH, which stays key-only)
EOF
}

dispatch_action "$@"
