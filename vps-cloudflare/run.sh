#!/bin/sh
# Cloudflare Tunnel + WARP internal network routes, as the internal network.
# Mutually exclusive with vps-tailscale. Env vars: see README.

set -eu
export DEBIAN_FRONTEND=noninteractive
zz-use zz-colors zz-log zz-install
# shellcheck disable=SC1091
. zz-colors

IFACE=vpscf0
IF_UNIT=/etc/systemd/system/vps-cloudflare-private.service
TUNNEL_UNIT=/etc/systemd/system/cloudflared.service
TUNNEL_ENV=/etc/cloudflared/tunnel.env

up() {
    local internal_ip

    # conflicts only guards one run: a host a previous run set up with Tailscale is
    # caught here.
    if systemctl is-active --quiet tailscaled 2>/dev/null || [ "$(vps-network internal-interface)" = "tailscale0" ]; then
        zz-log e "[vps-setup] Tailscale is set up on this host and is mutually exclusive with vps-cloudflare. Run 'sudo vps-setup --down-vps-tailscale' first (mind your SSH path), then re-run." && exit 1
    fi

    if [ -z "${SYSTEM_CLOUDFLARE_TUNNEL_TOKEN:-}" ] && [ ! -f "$TUNNEL_ENV" ]; then
        zz-log e "[vps-setup] SYSTEM_CLOUDFLARE_TUNNEL_TOKEN not set (Zero Trust > Networks > Tunnels > your tunnel > Install and run)." && exit 1
    fi

    # --- cloudflared
    if command -v cloudflared >/dev/null 2>&1; then
        zz-log i "[vps-setup] cloudflared already installed ($(cloudflared --version | head -n1 || true))."
    else
        zz-log i "[vps-setup] Installing cloudflared (release binary, works on any distribution)..."
        # SYSTEM_CLOUDFLARE_VERSION pins the release (and SYSTEM_CLOUDFLARE_SHA256 checks it); unset = latest.
        if [ -n "${SYSTEM_CLOUDFLARE_VERSION:-}" ]; then
            zz-install -u https://github.com/cloudflare/cloudflared/releases/download/{VERSION}/cloudflared-{OS}-{ARCH} \
                -v "$SYSTEM_CLOUDFLARE_VERSION" ${SYSTEM_CLOUDFLARE_SHA256:+-s "$SYSTEM_CLOUDFLARE_SHA256"} cloudflared
        else
            zz-install -u https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-{OS}-{ARCH} cloudflared
        fi
    fi

    # --- internal interface unit
    # WARP clients reach the VPS at this address through the tunnel's private
    # network route; it lives on a dummy interface so it exists before and without
    # any public traffic.
    internal_ip="${SYSTEM_CLOUDFLARE_INTERNAL_IP:-10.254.254.1}"
    cat >"$IF_UNIT" <<UNIT
[Unit]
Description=vps-setup internal interface for Cloudflare WARP routes
Before=network.target cloudflared.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'ip link add ${IFACE} type dummy 2>/dev/null || true; ip addr replace ${internal_ip}/32 dev ${IFACE}; ip link set ${IFACE} up'
ExecStop=/bin/sh -c 'ip link delete ${IFACE} 2>/dev/null || true'
[Install]
WantedBy=multi-user.target
UNIT

    # --- tunnel unit
    # The token goes in an owner-only env file, not in the (world-readable) unit.
    if [ -n "${SYSTEM_CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
        install -m 0700 -d "$(dirname "$TUNNEL_ENV")"
        (
            umask 077
            printf 'TUNNEL_TOKEN=%s\n' "$SYSTEM_CLOUDFLARE_TUNNEL_TOKEN" >"$TUNNEL_ENV"
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
    zz-log s "[vps-setup] cloudflared is running as a service; internal address ${internal_ip} on ${IFACE}."

    # Tell the other steps which interface carries the internal network (ufw rules
    # for access:"private" ports, the final summary); see vps-network.
    vps-network set-internal-interface "$IFACE"
}

down() {
    zz-log i "[vps-setup] Stopping the Cloudflare tunnel and removing its internal interface..."
    systemctl disable --now cloudflared.service vps-cloudflare-private.service 2>/dev/null || true
    rm -f "$TUNNEL_UNIT" "$IF_UNIT" "$TUNNEL_ENV"
    systemctl daemon-reload
    vps-network unset-internal-interface "$IFACE"
    if [ "${SYSTEM_CLOUDFLARE_PURGE:-false}" = "true" ]; then
        zz-log i "[vps-setup] Purging the cloudflared package (SYSTEM_CLOUDFLARE_PURGE=true)..."
        # Installed as a plain binary (no package to remove); also drop the apt repo of earlier installs.
        rm -f "$(command -v cloudflared)" /etc/apt/sources.list.d/cloudflared.list /usr/share/keyrings/cloudflare-main.gpg
    fi
    zz-log w "[vps-setup] The tunnel is down. Cockpit, Rancher, the Traefik" \
        "dashboard, and the k3s API (all private-access) are now unreachable" \
        "until you re-run this step's 'up' action."
    zz-log s "[vps-setup] Cloudflare tunnel brought down."
}

summary() {
    # Opt-in step: say nothing on a host that never installed it.
    [ -f "$IF_UNIT" ] || return 0
    vps-network summary-block "Internal network" - "$(vps-network internal-address) on ${IFACE} (Cloudflare Tunnel): connect with the WARP client" - \
        "add an internal network route for this /32 to the tunnel in Zero Trust"
}

case "${1:-}" in
    up | down) "$1" ;;
    summary) if command -v summary >/dev/null 2>&1; then summary; fi ;;
    *) zz-log e "Usage: $0 up|down|summary" && exit 1 ;;
esac
