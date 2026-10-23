#!/bin/sh
# Cloudflare Tunnel + WARP private network routes, as the private network.
# Mutually exclusive with vps-tailscale. Env vars: see README.

set -eu
zz-use "perspikapps/vps/vps-common@${ZZ_SETUP_REF:-main}" zz-persist
# shellcheck disable=SC1091
. vps-common

IFACE=vpscf0
IF_UNIT=/etc/systemd/system/vps-cloudflare-private.service
TUNNEL_UNIT=/etc/systemd/system/cloudflared.service
TUNNEL_ENV=/etc/cloudflared/tunnel.env

up() {
    local private_ip

    # conflicts only guards one run: a host a previous run set up with Tailscale is
    # caught here.
    if systemctl is-active --quiet tailscaled 2>/dev/null || [ "$(private_interface)" = "tailscale0" ]; then
        zz-log e "[vps-setup] Tailscale is set up on this host and is mutually exclusive with vps-cloudflare. Run 'sudo vps-setup --down-vps-tailscale' first (mind your SSH path), then re-run." && exit 1
    fi

    if [ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ] && [ ! -f "$TUNNEL_ENV" ]; then
        zz-log e "[vps-setup] CLOUDFLARE_TUNNEL_TOKEN not set (Zero Trust > Networks > Tunnels > your tunnel > Install and run)." && exit 1
    fi

    # --- cloudflared
    if command_exists cloudflared; then
        zz-log i "[vps-setup] cloudflared already installed ($(cloudflared --version | head -n1 || true))."
    else
        zz-log i "[vps-setup] Installing cloudflared from the Cloudflare apt repo..."
        install -m 0755 -d /usr/share/keyrings
        retry curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
        echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' >/etc/apt/sources.list.d/cloudflared.list
        # not apt_update_once: an earlier step may already have used its one update
        apt-get update -y
        apt_install cloudflared
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
    ok "cloudflared is running as a service; private address ${private_ip} on ${IFACE}."

    # Tell the other steps which interface carries the private network (ufw rules
    # for access:"private" ports, the final summary); see vps-common's private_interface.
    zz-persist -f "$VPS_PRIVATE_ACCESS_FILE" VPS_PRIVATE_INTERFACE "$IFACE"
}

down() {
    zz-log i "[vps-setup] Stopping the Cloudflare tunnel and removing its private interface..."
    systemctl disable --now cloudflared.service vps-cloudflare-private.service 2>/dev/null || true
    rm -f "$TUNNEL_UNIT" "$IF_UNIT" "$TUNNEL_ENV"
    systemctl daemon-reload
    [ ! -f "$VPS_PRIVATE_ACCESS_FILE" ] || sed -i "/^VPS_PRIVATE_INTERFACE=${IFACE}\$/d" "$VPS_PRIVATE_ACCESS_FILE"
    if [ "${PURGE_CLOUDFLARED:-false}" = "true" ]; then
        zz-log i "[vps-setup] Purging the cloudflared package (PURGE_CLOUDFLARED=true)..."
        apt_purge cloudflared || true
        rm -f /etc/apt/sources.list.d/cloudflared.list /usr/share/keyrings/cloudflare-main.gpg
    fi
    zz-log w "[vps-setup] The tunnel is down. Cockpit, Rancher, the Traefik" \
        "dashboard, and the k3s API (all private-access) are now unreachable" \
        "until you re-run this step's 'up' action."
    ok "Cloudflare tunnel brought down."
}

summary() {
    # Opt-in step: say nothing on a host that never installed it.
    [ -f "$IF_UNIT" ] || return 0
    echo " Private network:     $(private_address) (${IFACE}) via Cloudflare Tunnel - add a private network"
    echo "                       route for this /32 to the tunnel, and connect with the WARP client"
}

# verify <public-ip>: run it from ANOTHER machine, never on the VPS itself (a
# connection to its own public address is delivered locally and proves nothing).
# Every access:"private" port must time out or be refused from the internet.
verify() {
    local ip="$1" name port access note bad=0 tab

    tab="$(printf '\t')"
    while IFS="$tab" read -r name port access note; do
        [ "$access" = "private" ] || continue
        if curl -s -m 5 -o /dev/null "http://${ip}:${port}" 2>/dev/null || curl -sk -m 5 -o /dev/null "https://${ip}:${port}" 2>/dev/null; then
            zz-log e "[vps-setup] ${name} (${port}) answers on ${ip}: private port is exposed."
            bad=1
        else
            ok "${name} (${port}) is closed on ${ip}."
        fi
    done <<EOF
$(all_network_ports)
EOF
    return "$bad"
}

if [ "${1:-}" = "verify" ]; then
    VPS_SETUP_ROOT="${VPS_SETUP_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
    verify "${2:?usage: run.sh verify <public-ip> (from another machine)}"
    exit
fi

dispatch_action "$@"
