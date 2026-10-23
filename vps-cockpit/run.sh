#!/bin/sh
# Cockpit, on COCKPIT_HTTP_PORT/COCKPIT_HTTPS_PORT. Env vars: see README.

set -eu
export DEBIAN_FRONTEND=noninteractive
zz-use zz-colors zz-log zz-persist zz-install
# shellcheck disable=SC1091
. zz-colors
# A step only defines up(), down() and summary(): zz-setup sources it. An older zz-setup runs
# it as `run.sh <action>` and nothing would happen.
[ "$#" -eq 0 ] || { zz-log e "[vps-setup] $0 needs a newer zz-setup (config.functions); refresh it: zz-use -f zz-setup zz-call zz-vars zz-workspaces" && exit 1; }
# Scripts of this checkout, called (never sourced): addresses, private interface, ports.
vps_network="$(dirname "$0")/../vps-network/run.sh"

up() {
    local http_port https_port

    http_port="$("$vps_network" port cockpit_http)"
    https_port="$("$vps_network" port cockpit_https)"

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

    zz-log s "[vps-setup] Cockpit installed. Reachable at https://$("$vps_network" summary-host):${http_port} and :${https_port} (self-signed cert)."
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

    host="$("$vps_network" summary-host)"
    cat <<EOF2
 Cockpit:             https://${host}:$("$vps_network" port cockpit_http)
                       https://${host}:$("$vps_network" port cockpit_https)
                       user:     $(zz-persist -f "$VPS_SECRETS_FILE" -r COCKPIT_ADMIN_USER | grep . || echo 'not set - run vps-security/run.sh')
                       password: $(zz-persist -f "$VPS_SECRETS_FILE" -r COCKPIT_ADMIN_PASSWORD | grep . || echo 'not set - run vps-security/run.sh')
                       (saved to ${VPS_SECRETS_FILE}; PAM login, same
                       account you'd use on the local console - separate
                       from SSH, which stays key-only)
EOF2
}
