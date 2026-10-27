#!/bin/sh
# Tailscale. Env vars: see README.

set -eu
export DEBIAN_FRONTEND=noninteractive
zz-use zz-colors zz-log zz-install systemd-service zz-step
# shellcheck disable=SC1091
. zz-colors

up() {
    if command -v tailscale >/dev/null 2>&1; then
        zz-log i "Tailscale already installed ($(tailscale --version | head -n1 || true))."
    else
        zz-log i "Installing Tailscale from the official repo..."
        # The official installer needs bash.
        zz-install -u https://tailscale.com/install.sh -x bash tailscale
    fi

    zz-log i "Enabling tailscaled as a systemd service..."
    systemd-service up tailscaled
    zz-log s "tailscaled is running as a service ($(systemctl is-enabled tailscaled))."

    # Tell the other steps which interface carries the internal network (ufw rules
    # for access:"private" ports, the final summary); see vps-network.
    vps-network set-internal-interface tailscale0 100.64.0.0/10

    if [ -z "${TAILSCALE_AUTHKEY:-}" ]; then
        zz-log w "TAILSCALE_AUTHKEY not set. Run 'tailscale up' manually to join a tailnet and authenticate, then re-run: the step"
        exit 0
    fi

    zz-log i "Joining tailnet..."
    # shellcheck disable=SC2086
    tailscale up --authkey="${TAILSCALE_AUTHKEY}" --ssh ${TAILSCALE_EXTRA_ARGS:-}
    zz-log s "Tailscale is up: $(tailscale ip -4 2>/dev/null || echo 'pending')"
}

down() {
    if ! command -v tailscale >/dev/null 2>&1; then
        zz-log w "Tailscale not installed; nothing to do."
        return
    fi
    zz-log i "Logging out of the tailnet..."
    tailscale logout || true
    systemd-service down tailscaled
    vps-network unset-internal-interface tailscale0
    zz-log i "Removing the tailscale package..."
    zz-install -r tailscale || true
    zz-log w "Tailscale is disconnected. Private-access services are now unreachable" \
        "until you re-run this step's 'up' action."
    zz-log s "Tailscale brought down."
}

summary() {
    local iface ip

    iface="$(vps-network internal-interface)"
    ip="$(vps-network internal-address)"
    if [ -z "$iface" ]; then
        vps-network summary-block "Internal network" - "none: no interface (set SYSTEM_INTERNAL_INTERFACE, or run svc-tailscale)" -
    else
        vps-network summary-block "Internal network" - "${ip:-no address yet} on ${iface} (Tailscale): join the tailnet to reach the internal services" \
            "private-port services listen here and are closed to the internet"
    fi
}

. zz-step
