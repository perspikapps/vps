#!/bin/sh
# Cockpit, on COCKPIT_HTTP_PORT/COCKPIT_HTTPS_PORT. Env vars: see README.

set -eu
zz-use "perspikapps/vps/vps-common@${ZZ_SETUP_REF:-main}"
# vps-common comes from zz-use's download cache (24h for a branch). A copy from before
# the POSIX sh rewrite breaks under sh ("trap: ERR: bad trap"): refresh it when stale.
grep -q '^report_exit()' "$(command -v vps-common)" 2>/dev/null || zz-use --force "perspikapps/vps/vps-common@${ZZ_SETUP_REF:-main}"
# shellcheck disable=SC1091
. vps-common

up() {
    local http_port https_port

    http_port="$(net_port cockpit_http)"
    https_port="$(net_port cockpit_https)"

    zz-log i "[vps-setup] Installing Cockpit..."
    zz-install -m  cockpit cockpit-system cockpit-networkmanager cockpit-storaged cockpit-packagekit cockpit-files

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

    zz-log s "[vps-setup] Cockpit installed. Reachable at https://$(summary_host):${http_port} and :${https_port} (self-signed cert)."
}

down() {
    zz-log i "[vps-setup] Disabling Cockpit..."
    systemctl disable --now cockpit.socket 2>/dev/null || true
    rm -rf /etc/systemd/system/cockpit.socket.d
    systemctl daemon-reload
    zz-log i "[vps-setup] Removing Cockpit packages..."
    zz-install -r cockpit cockpit-system cockpit-networkmanager cockpit-storaged cockpit-packagekit cockpit-files || true
    zz-log s "[vps-setup] Cockpit removed."
}

summary() {
    local host

    host="$(summary_host)"
    cat <<EOF2
 Cockpit:             https://${host}:$(net_port cockpit_http)
                       https://${host}:$(net_port cockpit_https)
                       user:     $(zz-persist -f "$VPS_SECRETS_FILE" -r COCKPIT_ADMIN_USER | grep . || echo 'not set - run vps-security/run.sh')
                       password: $(zz-persist -f "$VPS_SECRETS_FILE" -r COCKPIT_ADMIN_PASSWORD | grep . || echo 'not set - run vps-security/run.sh')
                       (saved to ${VPS_SECRETS_FILE}; PAM login, same
                       account you'd use on the local console - separate
                       from SSH, which stays key-only)
EOF2
}

dispatch_action "$@"
