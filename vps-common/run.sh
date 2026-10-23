#!/bin/sh
# Shared helpers sourced via `zz-use perspikapps/vps/vps-common; . vps-common`.

set -eu
# pipefail is not in every POSIX sh (dash): use it where the shell has it.
# shellcheck disable=SC3040
(set -o pipefail) 2>/dev/null && set -o pipefail

zz-use zz-colors zz-log yaml-render zz-install zz-workspaces zz-persist zz-step kube-progress kube-diagnose kube-teardown kube-service-port kube-cert-manager
# shellcheck disable=SC1091
. zz-colors

export DEBIAN_FRONTEND=noninteractive

# Ports published by k3s (ServiceLB) or Docker are DNAT-ed past ufw; vps-security's
# vps-private-ports-guard unit re-inserts its FORWARD rule ahead of theirs. Call
# once k3s or Docker is up (best effort: the unit exists only after vps-security).
reapply_private_guard() {
    systemctl restart vps-private-ports-guard.service 2>/dev/null || true
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Value of the environment variable named $1 (empty when unset).
get_env() { eval "printf '%s' \"\${$1:-}\""; }

# Upper-cases stdin.
to_upper() { tr '[:lower:]' '[:upper:]'; }

# Caller's location ($0 is the step being run, not this file) - zz-use always
# reinstalls vps-common/run.sh under its own bin dir rather than reusing a checkout.
VPS_SETUP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Folders of this repo's installable steps (zz-workspaces: a bin file and an
# engines.zz-setup field), in config.order. Library folders (vps-common) and
# node_modules/* are left out.
feature_dirs() {
    local root tab

    root="$VPS_SETUP_ROOT"
    tab="$(printf '\037')"
    zz-workspaces "$root" | cut -d "$tab" -f3 | sed "s|^|${root}/|"
}

# Port <name> of the calling step (its own package.json). zz-setup exports every
# declared port as <NAME>_PORT (config.ports are inputs); the variable also wins
# when a step runs on its own.
net_port() {
    local name="$1" override value

    override="$(printf '%s' "$name" | to_upper)_PORT"
    value="$(get_env "$override")"
    if [ -n "$value" ]; then
        printf '%s\n' "$value"
        return 0
    fi
    jq -r --arg name "$name" '(.config.ports // [])[] | select(.name == $name) | .port' "$(cd "$(dirname "$0")" && pwd)/package.json"
}

# Every feature's ports as TSV (name, port, access, note); the port honours
# the same environment override as net_port.
all_network_ports() {
    local d name port access note override value tab

    tab="$(printf '\t')"
    while IFS= read -r d; do
        while IFS="$tab" read -r name port access note; do
            override="$(printf '%s' "$name" | to_upper)_PORT"
            value="$(get_env "$override")"
            printf '%s\t%s\t%s\t%s\n' "$name" "${value:-$port}" "$access" "$note"
        done <<EOF
$(jq -r '(.config.ports // [])[] | [.name, .port, .access, (.note // "")] | @tsv' "${d}/package.json")
EOF
    done <<EOF
$(feature_dirs)
EOF
}

# Private access: ports with access "private" are only reachable over one
# interface. Whoever provides that network says so by persisting
# VPS_PRIVATE_INTERFACE (vps-tailscale does on install, to the file below);
# a caller can also just set it (wg0, a LAN NIC...). The environment wins.
VPS_PRIVATE_ACCESS_FILE="${VPS_PRIVATE_ACCESS_FILE:-/etc/vps-private-access.env}"

private_interface() {
    if [ -n "${VPS_PRIVATE_INTERFACE:-}" ]; then
        printf '%s' "$VPS_PRIVATE_INTERFACE"
    elif [ -f "$VPS_PRIVATE_ACCESS_FILE" ]; then
        sed -n 's/^VPS_PRIVATE_INTERFACE=//p' "$VPS_PRIVATE_ACCESS_FILE" | tail -n1
    fi
}

# First IPv4 address of the private interface (empty when it has none yet).
private_address() {
    local iface

    iface="$(private_interface)"
    [ -z "$iface" ] || ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true
}

# Host for the URLs a step's summary prints: the private address, if any.
summary_host() {
    local ip

    ip="$(private_address)"
    printf '%s' "${ip:-<private-ip>}"
}

# Public IPv4 of this host: the default-route source address, or - behind NAT
# (a private address, as on some clouds) - what an external echo service sees.
public_ip() {
    local ip

    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") {print $(i + 1); exit}}' || true)"
    # empty, or private / loopback / link-local / CGNAT: behind NAT
    if [ -z "$ip" ] || printf '%s\n' "$ip" | grep -Eq '^(10\.|127\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|169\.254\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.)'; then
        ip="$(curl -fsS -m 5 https://api.ipify.org 2>/dev/null || true)"
    fi
    printf '%s' "$ip"
}

# Wildcard DNS: apps that need per-app subdomains (Coder's workspace apps) take
# one domain. vps-system persists WILDCARD_DOMAIN when it is set; the fallback
# is nip.io on the PUBLIC address (never the private/Tailscale one: the apps are
# served by the public ingress), which resolves any <a-b-c-d>.nip.io and
# *.<a-b-c-d>.nip.io to that IP with no DNS to set up.
VPS_WILDCARD_FILE="${VPS_WILDCARD_FILE:-/etc/vps-wildcard-domain.env}"

wildcard_domain() {
    local d="${WILDCARD_DOMAIN:-}" ip

    if [ -z "$d" ] && [ -f "$VPS_WILDCARD_FILE" ]; then
        d="$(sed -n 's/^WILDCARD_DOMAIN=//p' "$VPS_WILDCARD_FILE" | tail -n1)"
    fi
    if [ -z "$d" ]; then
        ip="$(public_ip)"
        [ -z "$ip" ] || d="$(printf '%s' "$ip" | tr . -).nip.io"
    fi
    printf '%s' "$d"
}

# Credentials generated or chosen by the steps (Cockpit login, Rancher bootstrap
# password) live as KEY=VALUE lines in this owner-only env file; the steps use
# zz-persist on it directly (-s -g to create, -r to read, -u to remove).
VPS_SECRETS_FILE="${VPS_SECRETS_FILE:-/root/.vps-secrets.env}"
