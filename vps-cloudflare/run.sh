#!/bin/sh
# Cloudflare Tunnel + WARP private network routes, as the private network.
# Mutually exclusive with vps-tailscale. Env vars: see README.

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

IFACE=vpscf0
IF_UNIT=/etc/systemd/system/vps-cloudflare-private.service
TUNNEL_UNIT=/etc/systemd/system/cloudflared.service
TUNNEL_ENV=/etc/cloudflared/tunnel.env

up() {
    local private_ip

    # conflicts only guards one run: a host a previous run set up with Tailscale is
    # caught here.
    if systemctl is-active --quiet tailscaled 2>/dev/null || [ "$("$vps_network" private-interface)" = "tailscale0" ]; then
        zz-log e "[vps-setup] Tailscale is set up on this host and is mutually exclusive with vps-cloudflare. Run 'sudo vps-setup --down-vps-tailscale' first (mind your SSH path), then re-run." && exit 1
    fi

    if [ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ] && [ ! -f "$TUNNEL_ENV" ]; then
        zz-log e "[vps-setup] CLOUDFLARE_TUNNEL_TOKEN not set (Zero Trust > Networks > Tunnels > your tunnel > Install and run)." && exit 1
    fi

    # --- cloudflared
    if command -v cloudflared >/dev/null 2>&1; then
        zz-log i "[vps-setup] cloudflared already installed ($(cloudflared --version | head -n1 || true))."
    else
        zz-log i "[vps-setup] Installing cloudflared from the Cloudflare apt repo..."
        install -m 0755 -d /usr/share/keyrings
        curl -fsSL --retry 5 --retry-delay 3 --retry-connrefused https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
        echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' >/etc/apt/sources.list.d/cloudflared.list
        # zz-install would skip the update (the index is under an hour old), but this repo is new
        apt-get update -y
        apt-get install -y --no-install-recommends cloudflared
    fi

    # --- private interface unit
    # WARP clients reach the VPS at this address through the tunnel's private
    # network route; it lives on a dummy interface so it exists before and without
    # any public traffic.
    private_ip="${CLOUDFLARE_PRIVATE_IP:-10.254.254.1}"
    cat >"$IF_UNIT" <<UNIT
[Unit]
Description=vps-setup private interface for Cloudflare WARP routes
Before=network.target cloudflared.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'ip link add ${IFACE} type dummy 2>/dev/null || true; ip addr replace ${private_ip}/32 dev ${IFACE}; ip link set ${IFACE} up'
ExecStop=/bin/sh -c 'ip link delete ${IFACE} 2>/dev/null || true'
[Install]
WantedBy=multi-user.target
UNIT

    # --- tunnel unit
    # The token goes in an owner-only env file, not in the (world-readable) unit.
    if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
        install -m 0700 -d "$(dirname "$TUNNEL_ENV")"
        (
            umask 077
            printf 'TUNNEL_TOKEN=%s\n' "$CLOUDFLARE_TUNNEL_TOKEN" >"$TUNNEL_ENV"
        )
    fi
    cat >"$TUNNEL_UNIT" <<UNIT
[Unit]
Description=Cloudflare Tunnel
After=network-online.target vps-cloudflare-private.service
Wants=network-online.target
[Service]
EnvironmentFile=${TUNNEL_ENV}
ExecStart=$(command -v cloudflared) --no-autoupdate tunnel run
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
UNIT

    systemctl daemon-reload
    systemctl enable --now vps-cloudflare-private.service
    systemctl enable --now cloudflared.service
    systemctl is-active --quiet cloudflared || { zz-log e "[vps-setup] cloudflared is not active after 'systemctl enable --now cloudflared' (check the token)." && exit 1; }
    zz-log s "[vps-setup] cloudflared is running as a service; private address ${private_ip} on ${IFACE}."

    # Tell the other steps which interface carries the private network (ufw rules
    # for access:"private" ports, the final summary); see vps-network.
    "$vps_network" set-private-interface "$IFACE"
}

down() {
    zz-log i "[vps-setup] Stopping the Cloudflare tunnel and removing its private interface..."
    systemctl disable --now cloudflared.service vps-cloudflare-private.service 2>/dev/null || true
    rm -f "$TUNNEL_UNIT" "$IF_UNIT" "$TUNNEL_ENV"
    systemctl daemon-reload
    "$vps_network" unset-private-interface "$IFACE"
    if [ "${PURGE_CLOUDFLARED:-false}" = "true" ]; then
        zz-log i "[vps-setup] Purging the cloudflared package (PURGE_CLOUDFLARED=true)..."
        zz-install -r cloudflared || true
        rm -f /etc/apt/sources.list.d/cloudflared.list /usr/share/keyrings/cloudflare-main.gpg
    fi
    zz-log w "[vps-setup] The tunnel is down. Cockpit, Rancher, the Traefik" \
        "dashboard, and the k3s API (all private-access) are now unreachable" \
        "until you re-run this step's 'up' action."
    zz-log s "[vps-setup] Cloudflare tunnel brought down."
}

summary() {
    # Opt-in step: say nothing on a host that never installed it.
    [ -f "$IF_UNIT" ] || return 0
    echo " Private network:     $("$vps_network" private-address) (${IFACE}) via Cloudflare Tunnel - add a private network"
    echo "                       route for this /32 to the tunnel, and connect with the WARP client"
}
