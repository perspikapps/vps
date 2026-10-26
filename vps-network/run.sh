#!/bin/sh
# vps-network <command> [args...] - the network facts and state of this VPS, in
# one place (a script, not a step): where it is reachable, which interface
# carries the internal network, which ports every step declares. Commands:
#   public-ip                       public IPv4 (behind NAT: what an echo service sees)
#   internal-interface               interface carrying the internal network (private-port services)
#   internal-address                 its first IPv4 address (empty until it has one)
#   summary-host                    that address, else <internal-ip>, for the summaries
#   external-domain                 the external DNS domain (EXTERNAL_DOMAIN, else nip.io)
#   port <name>                     a port by name (<NAME>_PORT wins over package.json)
#   ports                           every step's ports as TSV: name port access note
#   set-internal-interface <iface>   persist the internal interface (vps-tailscale, vps-cloudflare)
#   unset-internal-interface <iface> forget it again, when it is still <iface>
#   access-domain public|internal   the domain a service is reached on (public: external-domain; internal: internal-domain)
#   internal-domain                 INTERNAL_DOMAIN, else <internal-ip>.nip.io
#   visibility <service>            public or internal: env, persisted choice, config.visibility, else public
#   visibilities                    every service declaring config.visibility, as TSV: name, visibility
#   set-visibility <service> <v>    persist a choice (vps-access)
#   set-internal-domain <domain>    persist the internal domain (vps-access)
#   unset-access                    forget every access choice
#   set-external-domain <domain>    persist the external domain (vps-system)
#   verify <public-ip>              run from ANOTHER machine: every private port must be closed
#   reapply-guard                   re-insert the FORWARD guard of vps-security's private ports

set -eu
zz-use zz-colors zz-log zz-args zz-persist ws-list
# shellcheck disable=SC1091
. zz-colors

# --- arguments
eval "$(
    zz-args "Network facts and state of this VPS" "$0" "$@" <<help
- command command public-ip, internal-interface, internal-address, summary-host, external-domain, access-domain, internal-domain, visibility, visibilities, set-visibility, set-internal-domain, unset-access, port, ports, set-internal-interface, unset-internal-interface, set-external-domain, verify, reapply-guard
# params params Arguments of the command
help
)"

# --- parameters
if [ -z "$command" ]; then
    zz-log e "Usage: vps-network <command> [args...] (-h lists the commands)"
    exit 1
fi
# Where the steps are: this checkout, else VPS_SETUP_ROOT.
root="${VPS_SETUP_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# Internal network: ports with access "private" are only reachable over one interface.
# Whoever provides that network persists it here; the environment wins.
internal_file="${VPS_INTERNAL_ACCESS_FILE:-/etc/vps-internal-access.env}"
external_file="${VPS_EXTERNAL_DOMAIN_FILE:-/etc/vps-external-domain.env}"
# Access choices (vps-access): <NAME>_ACCESS per service and INTERNAL_DOMAIN; the environment wins.
access_file="${VPS_ACCESS_FILE:-/etc/vps-access.env}"

# --- functions

# get_port_override <name>: the value of <NAME>_PORT in the environment, if any.
get_port_override() {
    local name="$1" # port name, e.g. cockpit_http (mandatory)
    local var

    var="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')_PORT"
    eval "printf '%s' \"\${$var:-}\""
}

# get_public_ip: the default-route source address, or - behind NAT (a private
# address, as on some clouds) - what an external echo service sees.
get_public_ip() {
    local ip

    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") {print $(i + 1); exit}}' || true)"
    # empty, or private / loopback / link-local / CGNAT: behind NAT
    if [ -z "$ip" ] || printf '%s\n' "$ip" | grep -Eq '^(10\.|127\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|169\.254\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.)'; then
        ip="$(curl -fsS -m 5 https://api.ipify.org 2>/dev/null || true)"
    fi
    printf '%s' "$ip"
}

# get_internal_interface: VPS_INTERNAL_INTERFACE, else the persisted one.
get_internal_interface() {
    if [ -n "${VPS_INTERNAL_INTERFACE:-}" ]; then
        printf '%s' "$VPS_INTERNAL_INTERFACE"
    elif [ -f "$internal_file" ]; then
        zz-persist -f "$internal_file" -r VPS_INTERNAL_INTERFACE
    fi
}

# get_internal_address: first IPv4 address of the internal interface.
get_internal_address() {
    local iface

    iface="$(get_internal_interface)"
    [ -z "$iface" ] || ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true
}

# get_external_domain: apps that need per-app subdomains (Coder's workspace apps)
# take one domain: EXTERNAL_DOMAIN, the persisted one, else nip.io on the PUBLIC
# address (never the internal/Tailscale one: the apps are served by the public
# ingress), which resolves any <a-b-c-d>.nip.io and *.<a-b-c-d>.nip.io to that IP.
get_external_domain() {
    local domain="${EXTERNAL_DOMAIN:-}" ip

    if [ -z "$domain" ] && [ -f "$external_file" ]; then
        domain="$(zz-persist -f "$external_file" -r EXTERNAL_DOMAIN)"
    fi
    if [ -z "$domain" ]; then
        ip="$(get_public_ip)"
        [ -z "$ip" ] || domain="$(printf '%s' "$ip" | tr . -).nip.io"
    fi
    printf '%s' "$domain"
}

# get_internal_domain: INTERNAL_DOMAIN, else the persisted one, else nip.io on the
# internal (Tailscale/Cloudflare) address.
get_internal_domain() {
    local domain="${INTERNAL_DOMAIN:-}" ip

    if [ -z "$domain" ] && [ -f "$access_file" ]; then
        domain="$(zz-persist -f "$access_file" -r INTERNAL_DOMAIN)"
    fi
    if [ -z "$domain" ]; then
        ip="$(get_internal_address)"
        [ -z "$ip" ] || domain="$(printf '%s' "$ip" | tr . -).nip.io"
    fi
    printf '%s' "$domain"
}

# get_visibility <service>: public or internal. <NAME>_ACCESS from the environment,
# else the persisted choice, else config.visibility of vps-<service>, else public.
get_visibility() {
    local name="$1" var value

    var="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')_ACCESS"
    eval "value=\"\${$var:-}\""
    if [ -z "$value" ] && [ -f "$access_file" ]; then
        value="$(zz-persist -f "$access_file" -r "$var")"
    fi
    [ -n "$value" ] || value="$(jq -r '.config.visibility // empty' "$root/vps-$name/package.json" 2>/dev/null || true)"
    printf '%s' "${value:-public}"
}

# list_visibilities: every service that declares config.visibility, as TSV: name, visibility.
list_visibilities() {
    local dir name

    ws-list -b -e zz-setup "$root" | while IFS= read -r dir; do
        jq -e '.config.visibility' "$root/$dir/package.json" >/dev/null 2>&1 || continue
        name="${dir#./}"
        name="${name#vps-}"
        printf '%s\t%s\n' "$name" "$(get_visibility "$name")"
    done
}

# get_access_domain <public|internal>: the nip.io domain a service is reached on.
# public: the external domain; internal: the internal (Tailscale/Cloudflare) address.
get_access_domain() {
    local ip

    case "$1" in
        public) get_external_domain ;;
        internal)
            ip="$(get_internal_domain)"
            [ -n "$ip" ] || { echo "vps-network: no internal address: install vps-tailscale or vps-cloudflare for internal access" >&2 && return 1; }
            printf '%s' "$ip"
            ;;
        *) echo "usage: vps-network access-domain public|internal" >&2 && return 1 ;;
    esac
}

# list_ports: every step's ports as TSV (name, port, access, note); the port
# honours the same environment override as get_port.
list_ports() {
    local row dir name port access note value tab

    tab="$(printf '\t')"
    ws-list -b -e zz-setup "$root" | while IFS= read -r dir; do
        jq -r '(.config.ports // [])[] | [.name, .port, .access, (.note // "")] | @tsv' "$root/$dir/package.json"
    done | while IFS="$tab" read -r name port access note; do
        value="$(get_port_override "$name")"
        printf '%s\t%s\t%s\t%s\n' "$name" "${value:-$port}" "$access" "$note"
    done
}

# get_port <name>: <NAME>_PORT from the environment, else the port the steps declare.
get_port() {
    local name="$1" # port name (mandatory)
    local value

    value="$(get_port_override "$name")"
    if [ -n "$value" ]; then
        printf '%s\n' "$value"
        return 0
    fi
    list_ports | awk -F'\t' -v n="$name" '$1 == n { print $2; exit }'
}

# verify_ports <public-ip>: run it from ANOTHER machine, never on the VPS itself (a
# connection to its own public address is delivered locally and proves nothing).
# Every access:"private" port must time out or be refused from the internet.
verify_ports() {
    local ip="$1" # public address of the VPS (mandatory)
    local name port access note bad=0 tab

    tab="$(printf '\t')"
    while IFS="$tab" read -r name port access note; do
        [ "$access" = "private" ] || continue
        if curl -s -m 5 -o /dev/null "http://${ip}:${port}" 2>/dev/null || curl -sk -m 5 -o /dev/null "https://${ip}:${port}" 2>/dev/null; then
            zz-log e "${name} (${port}) answers on ${ip}: private port is exposed."
            bad=1
        else
            zz-log s "${name} (${port}) is closed on ${ip}."
        fi
    done <<EOF
$(list_ports)
EOF
    return "$bad"
}

# --- run
case "$command" in
public-ip) get_public_ip ;;
internal-interface) get_internal_interface ;;
internal-address) get_internal_address ;;
summary-host)
    ip="$(get_internal_address)"
    printf '%s' "${ip:-<internal-ip>}"
    ;;
external-domain) get_external_domain ;;
access-domain) get_access_domain "${1:-}" ;;
port) get_port "${1:?usage: vps-network port <name>}" ;;
ports) list_ports ;;
set-internal-interface) zz-persist -f "$internal_file" VPS_INTERNAL_INTERFACE "${1:?usage: vps-network set-internal-interface <iface>}" ;;
unset-internal-interface)
    [ "$(get_internal_interface)" != "${1:?usage: vps-network unset-internal-interface <iface>}" ] || zz-persist -q -f "$internal_file" -u VPS_INTERNAL_INTERFACE
    ;;
internal-domain) get_internal_domain ;;
visibility) get_visibility "${1:?usage: vps-network visibility <service>}" ;;
visibilities) list_visibilities ;;
set-visibility)
    case "${2:-}" in public | internal) ;; *) zz-log e "usage: vps-network set-visibility <service> public|internal" && exit 1 ;; esac
    zz-persist -f "$access_file" "$(printf '%s' "${1:?usage: vps-network set-visibility <service> public|internal}" | tr '[:lower:]' '[:upper:]')_ACCESS" "$2"
    ;;
set-internal-domain) zz-persist -f "$access_file" INTERNAL_DOMAIN "${1:?usage: vps-network set-internal-domain <domain>}" ;;
unset-access) rm -f "$access_file" ;;
set-external-domain) zz-persist -f "$external_file" EXTERNAL_DOMAIN "${1:?usage: vps-network set-external-domain <domain>}" ;;
verify) verify_ports "${1:?usage: vps-network verify <public-ip> (from another machine)}" ;;
reapply-guard)
    # ufw only filters INPUT; the guard unit of vps-security re-inserts its FORWARD rule
    # ahead of the ones k3s's ServiceLB and Docker add. Best effort: the unit exists
    # only after vps-security.
    systemctl restart vps-private-ports-guard.service 2>/dev/null || true
    ;;
*)
    zz-log e "Unknown command '$command' (public-ip, internal-interface, internal-address, summary-host, external-domain, access-domain, internal-domain, visibility, visibilities, set-visibility, set-internal-domain, unset-access, port, ports, set-internal-interface, unset-internal-interface, set-external-domain, verify, reapply-guard)"
    exit 1
    ;;
esac
