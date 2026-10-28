#!/bin/sh
# vps-network <command> [args...] - the network facts and state of this VPS, in
# one place (a script, not a step): where it is reachable, which interface
# carries the internal network, which ports every step declares. Commands:
#   public-ip                       public IPv4 (behind NAT: what an echo service sees)
#   internal-interface               interface carrying the internal network (private-port services)
#   internal-address                 its first IPv4 address (empty until it has one)
#   summary-host                    that address, else <internal-ip>, for the summaries
#   external-domain                 the external DNS domain (SYSTEM_EXTERNAL_DOMAIN, else nip.io)
#   summary-block <title> <public> <internal> <local> [note...]   the public/internal/local paragraph of a step summary
#   port <name>                     a port by name (<NAME>_PORT wins over package.json)
#   ports                           every step's ports as TSV: name port access note
#   set-internal-interface <iface> [<range>]  persist the internal interface and, optionally, the source CIDRs of its clients (svc-tailscale, svc-cloudflare)
#   unset-internal-interface <iface> forget it again, when it is still <iface>
#   access-domain public|internal   the domain a service is reached on (public: external-domain; internal: internal-domain)
#   access-route <service>          shell to eval: route_access, route_domain, route_middlewares, route_certresolver of a service
#   internal-range                  source CIDRs of the internal network's clients: what the provider declared, else the internal address and loopback
#   internal-domain                 SYSTEM_INTERNAL_DOMAIN, else the saved one, else the external domain
#   visibility <service>            public or internal: env, persisted choice, config.visibility, else public
#   visibilities                    every service declaring config.visibility, as TSV: name, visibility
#   set-visibility <service> <v>    persist a choice (vps-access)
#   set-internal-domain <domain>    persist the internal domain (vps-access)
#   unset-access                    forget every access choice
#   set-external-domain <domain>    persist the external domain (vps-system)
#   registry-url                    host:port of the local image registry (SYSTEM_REGISTRY_URL, else the saved one, else "none")
#   set-registry-url <host:port>    persist it (the step that installs a local registry)
#   unset-registry-url              forget it again (back to "none")
#   verify <public-ip>              run from ANOTHER machine: every private port must be closed
#   reapply-guard                   re-insert the FORWARD guard of vps-security's private ports

set -eu
zz-use zz-colors zz-log zz-args zz-persist ws-list
# shellcheck disable=SC1091
. zz-colors

# --- arguments
eval "$(
    zz-args "Network facts and state of this VPS" "$0" "$@" <<help
- command command public-ip, internal-interface, internal-address, summary-host, external-domain, access-domain, internal-domain, internal-range, access-route, summary-block, visibility, visibilities, set-visibility, set-internal-domain, unset-access, port, ports, set-internal-interface, unset-internal-interface, set-external-domain, registry-url, set-registry-url, unset-registry-url, verify, reapply-guard
# params params Arguments of the command
help
)"

# --- parameters
if [ -z "$command" ]; then
    zz-log e "Usage: vps-network <command> [args...] (-h lists the commands)"
    exit 1
fi
# Where the steps are: VPS_SETUP_ROOT, else ZZ_SETUP_ROOT (zz-setup exports it: an installed
# bin is a copy), else the checkout this script sits in.
root="${VPS_SETUP_ROOT:-${ZZ_SETUP_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}}"
# Everything persisted here lives in one file; the environment wins. It holds the internal
# interface and its source range (whoever provides the internal network sets them), the external
# domain, and vps-access's choices: SYSTEM_ACCESS_<SERVICE> per service and the internal domain.
state_file="${SYSTEM_NETWORK_FILE:-/etc/vps-network.env}"
internal_file="$state_file" external_file="$state_file" access_file="$state_file"
# Older versions kept those in three files: fold them in once.
if [ -z "${SYSTEM_NETWORK_FILE:-}" ]; then
    for old in /etc/vps-internal-access.env /etc/vps-external-domain.env /etc/vps-access.env; do
        [ -f "$old" ] || continue
        while IFS= read -r line; do
            case "$line" in [A-Z]*=*) zz-persist -q -f "$state_file" "${line%%=*}" "${line#*=}" ;; esac
        done <"$old"
        rm -f "$old"
    done
fi

# --- functions

# get_port_override <name>: the value of <NAME>_PORT in the environment, if any.
get_port_override() {
    local name="$1" # port name, e.g. cockpit_http (mandatory)
    local var

    var="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')_PORT"
    eval "printf '%s' \"\${$var:-}\""
}

# get_public_ip: the instance address, the source of the default route.
get_public_ip() {
    ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") {print $(i + 1); exit}}' || true
}

# get_internal_interface: SYSTEM_INTERNAL_INTERFACE, else the persisted one.
get_internal_interface() {
    if [ -n "${SYSTEM_INTERNAL_INTERFACE:-}" ]; then
        printf '%s' "$SYSTEM_INTERNAL_INTERFACE"
    elif [ -f "$internal_file" ]; then
        zz-persist -f "$internal_file" -r SYSTEM_INTERNAL_INTERFACE
    fi
}

# get_internal_address: first IPv4 address of the internal interface.
get_internal_address() {
    local iface

    iface="$(get_internal_interface)"
    [ -z "$iface" ] || ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true
}

# get_external_domain: apps that need per-app subdomains (Coder's workspace apps)
# take one domain: SYSTEM_EXTERNAL_DOMAIN, the persisted one, else nip.io on the PUBLIC
# address (never the internal/Tailscale one: the apps are served by the public
# ingress), which resolves any <a-b-c-d>.nip.io and *.<a-b-c-d>.nip.io to that IP.
get_external_domain() {
    local domain="${SYSTEM_EXTERNAL_DOMAIN:-}" ip

    domain="${domain#\*.}"
    if [ -z "$domain" ] && [ -f "$external_file" ]; then
        domain="$(zz-persist -f "$external_file" -r SYSTEM_EXTERNAL_DOMAIN)"
    fi
    if [ -z "$domain" ]; then
        ip="$(get_public_ip)"
        [ -z "$ip" ] || domain="$(printf '%s' "$ip" | tr . -).nip.io"
    fi
    printf '%s' "$domain"
}

# get_internal_domain: SYSTEM_INTERNAL_DOMAIN, else the persisted one, else the external domain.
get_internal_domain() {
    local domain="${SYSTEM_INTERNAL_DOMAIN:-}"

    if [ -z "$domain" ] && [ -f "$access_file" ]; then
        domain="$(zz-persist -f "$access_file" -r SYSTEM_INTERNAL_DOMAIN)"
    fi
    [ -n "$domain" ] || domain="$(get_external_domain)"
    printf '%s' "$domain"
}

# get_registry_url: the local registry's host:port (SYSTEM_REGISTRY_URL, else the persisted one), else "none".
get_registry_url() {
    local url="${SYSTEM_REGISTRY_URL:-}"

    if [ -z "$url" ] && [ -f "$state_file" ]; then
        url="$(zz-persist -f "$state_file" -r SYSTEM_REGISTRY_URL)"
    fi
    printf '%s' "${url:-none}"
}

# in_list <name> <comma list>: whether the name is in the list.
in_list() {
    case ",$2," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

# get_visibility <service>: public or internal, from the system config only: SYSTEM_INTERNAL_APPS /
# SYSTEM_PUBLIC_APPS (comma lists, for unattended runs), else the choice vps-access persisted, else
# config.visibility of vps-<service> or app-<service>, else public.
get_visibility() {
    local name="$1" value="" dir

    if in_list "$name" "${SYSTEM_INTERNAL_APPS:-}"; then
        value=internal
    elif in_list "$name" "${SYSTEM_PUBLIC_APPS:-}"; then
        value=public
    elif [ -f "$access_file" ]; then
        value="$(zz-persist -f "$access_file" -r "SYSTEM_ACCESS_$(printf '%s' "$name" | tr '[:lower:]-' '[:upper:]_')")"
    fi
    if [ -z "$value" ]; then
        for dir in "vps-$name" "app-$name" "svc-$name" "$name"; do
            [ -f "$root/$dir/package.json" ] || continue
            value="$(jq -r '.config.visibility // empty' "$root/$dir/package.json" 2>/dev/null || true)"
            break
        done
    fi
    printf '%s' "${value:-public}"
}

# list_visibilities: every service that declares config.visibility, as TSV: name, visibility.
list_visibilities() {
    local dir name

    ws-list -b -e zz-setup "$root" | while IFS= read -r dir; do
        jq -e '.config.visibility' "$root/$dir/package.json" >/dev/null 2>&1 || continue
        # under zz-setup (ZZ_SETUP_UP set): only the apps this run brings up
        case "${ZZ_SETUP_UP:-}" in "") ;; *" ${dir#./} "*) ;; *) continue ;; esac
        name="${dir#./}"
        name="${name#vps-}"
        name="${name#app-}"
        name="${name#svc-}"
        printf '%s\t%s\n' "$name" "$(get_visibility "$name")"
    done
}

# get_internal_range: the source CIDRs of the internal network's clients (comma separated):
# the range the provider declared when it set the interface (SYSTEM_INTERNAL_SOURCE_RANGE), else
# this host's internal address and loopback. Empty until there is an internal network.
get_internal_range() {
    local ip range

    [ ! -f "$internal_file" ] || range="$(zz-persist -f "$internal_file" -r SYSTEM_INTERNAL_SOURCE_RANGE)"
    if [ -n "${range:-}" ]; then
        printf '%s' "$range"
        return 0
    fi
    ip="$(get_internal_address)"
    [ -z "$ip" ] || printf '%s/32,127.0.0.1/32' "$ip"
}

# get_access_domain <public|internal>: the nip.io domain a service is reached on.
# public: the external domain; internal: the internal (Tailscale/Cloudflare) address.
get_access_domain() {
    local ip

    case "$1" in
        public) get_external_domain ;;
        internal)
            ip="$(get_internal_domain)"
            [ -n "$ip" ] || { echo "vps-network: no domain for internal access (set SYSTEM_INTERNAL_DOMAIN or SYSTEM_EXTERNAL_DOMAIN)" >&2 && return 1; }
            printf '%s' "$ip"
            ;;
        *) echo "usage: vps-network access-domain public|internal" >&2 && return 1 ;;
    esac
}

# summary_block <title> <public> <internal> <local> [note...]: the paragraph every step
# summary prints. An empty or "-" scope reads "none"; notes follow, one per line.
summary_block() {
    local title="$1" scope text

    printf ' %s:\n' "$title"
    shift
    for scope in Public Internal Local; do
        text="${1:--}"
        [ -n "$text" ] || text="-"
        [ "$text" != "-" ] || text="none"
        printf '   %-9s  %s\n' "${scope}:" "$text"
        shift
    done
    for text in "$@"; do printf '   %s\n' "$text"; done
}

# get_access_route <service>: shell to eval, the route of a service from its public/internal
# choice: route_access, route_domain, route_middlewares (the internal-only Traefik middleware
# for internal, else empty) and route_certresolver (Let's Encrypt for public, none for internal).
# On an invalid choice or a missing domain it logs and prints "exit 1" for the caller.
get_access_route() {
    local access domain middlewares certresolver

    access="$(get_visibility "$1")"
    case "$access" in
        public) middlewares="" certresolver="letsencrypt" ;;
        internal) middlewares="kube-system-internal-only@kubernetescrd" certresolver="" ;;
        *) echo "vps-network: $1 must be public or internal (got '${access}')" >&2 && echo 'exit 1' && return 0 ;;
    esac
    domain="$(get_access_domain "$access")" || { echo 'exit 1' && return 0; }
    printf "route_access='%s'\nroute_domain='%s'\nroute_middlewares='%s'\nroute_certresolver='%s'\n" "$access" "$domain" "$middlewares" "$certresolver"
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
summary-block) summary_block "$@" ;;
port) get_port "${1:?usage: vps-network port <name>}" ;;
ports) list_ports ;;
set-internal-interface)
    zz-persist -f "$internal_file" SYSTEM_INTERNAL_INTERFACE "${1:?usage: vps-network set-internal-interface <iface> [<source-range>]}"
    # the source CIDRs of the network's clients, declared by the provider (used by the internal-only middleware)
    [ -z "${2:-}" ] || zz-persist -f "$internal_file" SYSTEM_INTERNAL_SOURCE_RANGE "$2"
    ;;
unset-internal-interface)
    if [ "$(get_internal_interface)" = "${1:?usage: vps-network unset-internal-interface <iface>}" ]; then
        zz-persist -q -f "$internal_file" -u SYSTEM_INTERNAL_INTERFACE
        zz-persist -q -f "$internal_file" -u SYSTEM_INTERNAL_SOURCE_RANGE
    fi
    ;;
internal-domain) get_internal_domain ;;
internal-range) get_internal_range ;;
access-route) get_access_route "${1:?usage: vps-network access-route <service>}" ;;
visibility) get_visibility "${1:?usage: vps-network visibility <service>}" ;;
visibilities) list_visibilities ;;
set-visibility)
    case "${2:-}" in public | internal) ;; *) zz-log e "usage: vps-network set-visibility <service> public|internal" && exit 1 ;; esac
    zz-persist -f "$access_file" "SYSTEM_ACCESS_$(printf '%s' "${1:?usage: vps-network set-visibility <service> public|internal}" | tr '[:lower:]-' '[:upper:]_')" "$2"
    ;;
set-internal-domain) zz-persist -f "$access_file" SYSTEM_INTERNAL_DOMAIN "${1:?usage: vps-network set-internal-domain <domain>}" ;;
unset-access)
    [ ! -f "$access_file" ] || zz-persist -q -f "$access_file" -u "SYSTEM_INTERNAL_DOMAIN $(sed -n 's/^\(SYSTEM_ACCESS_[A-Z0-9_]*\)=.*/\1/p' "$access_file" | tr '\n' ' ')"
    ;;
set-external-domain) zz-persist -f "$external_file" SYSTEM_EXTERNAL_DOMAIN "${1:?usage: vps-network set-external-domain <domain>}" ;;
registry-url) get_registry_url ;;
set-registry-url) zz-persist -f "$state_file" SYSTEM_REGISTRY_URL "${1:?usage: vps-network set-registry-url <host:port>}" ;;
unset-registry-url) zz-persist -q -f "$state_file" -u SYSTEM_REGISTRY_URL ;;
verify) verify_ports "${1:?usage: vps-network verify <public-ip> (from another machine)}" ;;
reapply-guard)
    # ufw only filters INPUT; the guard unit of vps-security re-inserts its FORWARD rule
    # ahead of the ones k3s's ServiceLB and Docker add. Best effort: the unit exists
    # only after vps-security.
    systemctl restart vps-private-ports-guard.service 2>/dev/null || true
    ;;
*)
    zz-log e "Unknown command '$command' (public-ip, internal-interface, internal-address, summary-host, external-domain, access-domain, internal-domain, internal-range, access-route, summary-block, visibility, visibilities, set-visibility, set-internal-domain, unset-access, port, ports, set-internal-interface, unset-internal-interface, set-external-domain, registry-url, set-registry-url, unset-registry-url, verify, reapply-guard)"
    exit 1
    ;;
esac
