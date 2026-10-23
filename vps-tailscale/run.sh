#!/bin/sh
# Tailscale. Env vars: see README.

set -eu
export DEBIAN_FRONTEND=noninteractive
zz-use zz-colors zz-log zz-install
# shellcheck disable=SC1091
. zz-colors
# A step only defines up(), down() and summary(): zz-setup sources it. An older zz-setup runs
# it as `run.sh <action>` and nothing would happen.
[ "$#" -eq 0 ] || { zz-log e "[vps-setup] $0 needs a newer zz-setup (config.functions); refresh it: zz-use -f zz-setup zz-call zz-vars zz-workspaces" && exit 1; }
# Scripts of this checkout, called (never sourced): addresses, private interface, ports.
vps_network="$(dirname "$0")/../vps-network/run.sh"

up() {
    if command -v tailscale >/dev/null 2>&1; then
        zz-log i "[vps-setup] Tailscale already installed ($(tailscale --version | head -n1 || true))."
    else
        zz-log i "[vps-setup] Installing Tailscale from the official repo..."
        # The official installer needs bash.
        zz-install -u https://tailscale.com/install.sh -x bash tailscale
    fi

    zz-log i "[vps-setup] Enabling tailscaled as a systemd service..."
    systemctl enable --now tailscaled
    systemctl is-active --quiet tailscaled || { zz-log e "[vps-setup] tailscaled is not active after 'systemctl enable --now tailscaled'." && exit 1; }
    zz-log s "[vps-setup] tailscaled is running as a service ($(systemctl is-enabled tailscaled))."

    # Tell the other steps which interface carries the private network (ufw rules
    # for access:"private" ports, the final summary); see vps-network.
    "$vps_network" set-private-interface tailscale0

    if [ -z "${TAILSCALE_AUTHKEY:-}" ]; then
        zz-log w "[vps-setup] TAILSCALE_AUTHKEY not set. Run 'tailscale up' manually to join a tailnet and authenticate, then re-run: sudo vps-setup --only-vps-tailscale"
        exit 0
    fi

    zz-log i "[vps-setup] Joining tailnet..."
    # shellcheck disable=SC2086
    tailscale up --authkey="${TAILSCALE_AUTHKEY}" --ssh ${TAILSCALE_EXTRA_ARGS:-}
    zz-log s "[vps-setup] Tailscale is up: $(tailscale ip -4 2>/dev/null || echo 'pending')"
}

down() {
    if ! command -v tailscale >/dev/null 2>&1; then
        zz-log w "[vps-setup] Tailscale not installed; nothing to do."
        return
    fi
    zz-log i "[vps-setup] Logging out of the tailnet..."
    tailscale logout || true
    systemctl disable --now tailscaled || true
    "$vps_network" unset-private-interface tailscale0
    if [ "${PURGE_TAILSCALE:-false}" = "true" ]; then
        zz-log i "[vps-setup] Purging the tailscale package (PURGE_TAILSCALE=true)..."
        zz-install -r tailscale || true
    fi
    zz-log w "[vps-setup] Tailscale is disconnected. Cockpit, Rancher, the Traefik" \
        "dashboard, and the k3s API (all private-access) are now unreachable" \
        "until you re-run this step's 'up' action."
    zz-log s "[vps-setup] Tailscale brought down."
}

summary() {
    local iface ip

    iface="$("$vps_network" private-interface)"
    ip="$("$vps_network" private-address)"
    if [ -z "$iface" ]; then
        echo " Private network:     none - private-access ports are closed (set VPS_PRIVATE_INTERFACE, or run vps-tailscale)"
    elif [ -z "$ip" ]; then
        echo " Private network:     ${iface} (no address yet - join the private network)"
    else
        echo " Private network:     ${ip} (${iface})"
    fi
}
