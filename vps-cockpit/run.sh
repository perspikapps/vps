#!/bin/sh
# Cockpit, on COCKPIT_HTTP_PORT/COCKPIT_HTTPS_PORT. Env vars: see README.

set -eu
zz-use "perspikapps/vps/vps-common@${ZZ_SETUP_REF:-main}"
# shellcheck disable=SC1091
. vps-common

up() {
    local http_port https_port

    apt_update_once

    http_port="$(net_port cockpit_http)"
    https_port="$(net_port cockpit_https)"

    zz-log i "[vps-setup] Installing Cockpit..."
    apt_install cockpit cockpit-system cockpit-networkmanager cockpit-storaged cockpit-packagekit cockpit-files

    zz-log i "[vps-setup] Configuring cockpit.socket to listen on ${http_port} and ${https_port}..."
    mkdir -p /etc/systemd/system/cockpit.socket.d
    cat >/etc/systemd/system/cockpit.socket.d/override.conf <<EOF2
[Socket]
ListenStream=
ListenStream=${http_port}
ListenStream=${https_port}
EOF2

    systemctl daemon-reload
    systemctl enable --now cockpit.socket
    systemctl restart cockpit.socket

    ok "Cockpit installed. Reachable at https://$(summary_host):${http_port} and :${https_port} (self-signed cert)."
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
    cat <<EOF2
 Cockpit:             https://${host}:$(net_port cockpit_http)
                       https://${host}:$(net_port cockpit_https)
                       user:     $(vps_secret COCKPIT_ADMIN_USER /root/.cockpit-admin-user | grep . || echo 'not set - run vps-security/run.sh')
                       password: $(vps_secret COCKPIT_ADMIN_PASSWORD /root/.cockpit-admin-password | grep . || echo 'not set - run vps-security/run.sh')
                       (saved to ${VPS_SECRETS_FILE}; PAM login, same
                       account you'd use on the local console - separate
                       from SSH, which stays key-only)
EOF2
}

dispatch_action "$@"
