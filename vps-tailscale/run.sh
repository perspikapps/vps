#!/bin/sh
# Tailscale. Env vars: see README.

set -eu
# Source the vps-common of this checkout (always the version of the step); a step
# installed on its own gets the one zz-use fetches.
common="$(dirname "$0")/../vps-common/run.sh"
if [ ! -f "$common" ]; then
    zz-use "perspikapps/vps/vps-common@${ZZ_SETUP_REF:-main}"
    common="$(command -v vps-common)"
fi
# shellcheck disable=SC1090
. "$common"

up() {
    if command_exists tailscale; then
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
    # for access:"private" ports, the final summary); see vps-common's private_interface.
    zz-persist -f "$VPS_PRIVATE_ACCESS_FILE" VPS_PRIVATE_INTERFACE tailscale0

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
    if ! command_exists tailscale; then
        zz-log w "[vps-setup] Tailscale not installed; nothing to do."
        return
    fi
    zz-log i "[vps-setup] Logging out of the tailnet..."
    tailscale logout || true
    systemctl disable --now tailscaled || true
    [ ! -f "$VPS_PRIVATE_ACCESS_FILE" ] || sed -i '/^VPS_PRIVATE_INTERFACE=tailscale0$/d' "$VPS_PRIVATE_ACCESS_FILE"
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

    iface="$(private_interface)"
    ip="$(private_address)"
    if [ -z "$iface" ]; then
        echo " Private network:     none - private-access ports are closed (set VPS_PRIVATE_INTERFACE, or run vps-tailscale)"
    elif [ -z "$ip" ]; then
        echo " Private network:     ${iface} (no address yet - join the private network)"
    else
        echo " Private network:     ${ip} (${iface})"
    fi
}

. zz-step
