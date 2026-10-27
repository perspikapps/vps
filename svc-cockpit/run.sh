#!/bin/sh
# Cockpit, on COCKPIT_HTTP_PORT/COCKPIT_HTTPS_PORT. Env vars: see README.

set -eu
export DEBIAN_FRONTEND=noninteractive
zz-use zz-colors zz-log zz-persist zz-install
# shellcheck disable=SC1091
. zz-colors

up() {
    local http_port https_port

    http_port="$(vps-network port cockpit_http)"
    https_port="$(vps-network port cockpit_https)"

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

    zz-log s "[vps-setup] Cockpit installed. Reachable at https://$(vps-network summary-host):${http_port} and :${https_port} (self-signed cert)."
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

    host="$(vps-network summary-host)"
    vps-network summary-block Cockpit - \
        "https://${host}:$(vps-network port cockpit_http) and https://${host}:$(vps-network port cockpit_https) (internal address, private port)" \
        "https://localhost:$(vps-network port cockpit_http) and https://localhost:$(vps-network port cockpit_https) (on the VPS)" \
        "user:     $(zz-persist -f "$SYSTEM_SECRETS_FILE" -r COCKPIT_ADMIN_USER | grep . || echo 'not set - run vps-security/run.sh')" \
        "password: $(zz-persist -f "$SYSTEM_SECRETS_FILE" -r COCKPIT_ADMIN_PASSWORD | grep . || echo 'not set - run vps-security/run.sh')" \
        "(saved to ${SYSTEM_SECRETS_FILE}; PAM login, same account you'd use on the local console - separate from SSH, which stays key-only)"
}

case "${1:-}" in
    up | down) "$1" ;;
    summary) if command -v summary >/dev/null 2>&1; then summary; fi ;;
    *) zz-log e "Usage: $0 up|down|summary" && exit 1 ;;
esac
