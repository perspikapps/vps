#!/bin/sh
# Cockpit, on COCKPIT_HTTP_PORT/COCKPIT_HTTPS_PORT. Env vars: see README.

set -eu
export DEBIAN_FRONTEND=noninteractive
zz-use zz-colors zz-log zz-persist zz-install systemd-service zz-step
# shellcheck disable=SC1091
. zz-colors

up() {
    local http_port https_port

    http_port="$(vps-network port cockpit_http)"
    https_port="$(vps-network port cockpit_https)"

    zz-log i "Installing Cockpit..."
    zz-install -m  cockpit cockpit-system cockpit-networkmanager cockpit-storaged cockpit-packagekit cockpit-files

    zz-log i "Configuring cockpit.socket to listen on ${http_port} and ${https_port}..."
    mkdir -p /etc/systemd/system/cockpit.socket.d
    cat >/etc/systemd/system/cockpit.socket.d/override.conf <<EOF2
[Socket]
ListenStream=
ListenStream=${http_port}
ListenStream=${https_port}
EOF2

    systemctl daemon-reload
    systemd-service -r up cockpit.socket

    zz-log s "Cockpit installed. Reachable at https://$(vps-network summary-host):${http_port} and :${https_port} (self-signed cert)."
}

down() {
    zz-log i "Disabling Cockpit..."
    systemd-service down cockpit.socket
    rm -rf /etc/systemd/system/cockpit.socket.d
    systemctl daemon-reload
    zz-log i "Removing Cockpit packages..."
    zz-install -r cockpit cockpit-system cockpit-networkmanager cockpit-storaged cockpit-packagekit cockpit-files || true
    zz-log s "Cockpit removed."
}

summary() {
    local host

    host="$(vps-network summary-host)"
    vps-network summary-block Cockpit - \
        "https://${host}:$(vps-network port cockpit_http) and https://${host}:$(vps-network port cockpit_https) (internal address, private port)" \
        "https://localhost:$(vps-network port cockpit_http) and https://localhost:$(vps-network port cockpit_https) (on the VPS)" \
        "user:     $(zz-persist -S -r -v 'not set - run vps-security/run.sh' COCKPIT_ADMIN_USER)" \
        "password: $(zz-persist -S -r -v 'not set - run vps-security/run.sh' COCKPIT_ADMIN_PASSWORD)" \
        "(saved to ${ZZ_SECRETS_FILE}; PAM login, same account you'd use on the local console - separate from SSH, which stays key-only)"
}

. zz-step
