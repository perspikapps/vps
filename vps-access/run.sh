#!/bin/sh
# Confirms which services are public (server IP) or internal (Tailscale/Cloudflare
# address), and the DNS domains they are reached on. Env vars: see README.
# A zz-setup step: configured by environment inputs (package.json config.inputs),
# run with up, down or summary as its first argument. The menus only run on a terminal.

set -eu
zz-use zz-colors zz-log zz-menu zz-prompt zz-interactive zz-step
# shellcheck disable=SC1091
. zz-colors

# ask: menus only with something to ask on (zz-interactive: a terminal, not ZZ_INTERACTIVE=0).
ask() { zz-interactive; }

# confirm_interface: when no step declared the internal interface and SYSTEM_INTERNAL_INTERFACE is
# not set, pick it from the host's interfaces (the default-route one is the public side, marked).
confirm_interface() {
    local iface default choice addr

    ask || return 0
    [ -z "$(vps-network internal-interface)" ] || return 0
    default="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
    set --
    for iface in $(ip -o link show 2>/dev/null | awk -F': ' '{sub(/@.*/, "", $2); print $2}'); do
        # the container/cluster plumbing is never the internal network
        case "$iface" in lo | docker* | veth* | br-* | cni* | flannel* | cali* | kube* | virbr* | lxc*) continue ;; esac
        addr="$(ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4; exit}' | cut -d/ -f1)"
        set -- "$@" "${iface}=${iface}${addr:+ ($addr)}$([ "$iface" != "$default" ] || printf ' - default route, public')"
    done
    [ "$#" -gt 0 ] || return 0
    choice="$(zz-menu -t "Internal interface (SYSTEM_INTERNAL_INTERFACE is not set)" \
        -f "  Number picks the interface (or none); q keeps it unset." "$@" "none=None (no internal network)")" || return 0
    [ -n "$choice" ] && [ "$choice" != none ] || return 0
    vps-network set-internal-interface "$choice"
    zz-log i "Internal interface: ${choice}"
}

# confirm_visibility: public or internal for every service declaring config.visibility.
confirm_visibility() {
    local name vis out key state tab

    ask || return 0
    tab="$(printf '\t')"
    set --
    while IFS="$tab" read -r name vis; do
        [ -z "$name" ] || set -- "$@" "${name}:${vis}=${name}"
    done <<EOF
$(vps-network visibilities)
EOF
    [ "$#" -gt 0 ] || return 0
    out="$(zz-menu -t "Visibility" -f "  Number cycles public/internal; <enter> confirms; q keeps." -c public,internal "$@")" || return 0
    while IFS== read -r key state; do
        [ -n "$key" ] || continue
        if [ "$state" = "internal" ] && [ -z "$(vps-network internal-address)" ]; then
            zz-log w "${key}: no internal address (install svc-tailscale or svc-cloudflare); keeping it public."
            state=public
        fi
        vps-network set-visibility "$key" "$state"
    done <<EOF
$out
EOF
}

# confirm_domain <label> <domain> <ip> <persist command> [<default domain>]: ask for the domain
# (empty or unresolved: fall back to <ip>.nip.io, which always resolves), then save it. A
# domain left at the default (the internal one defaults to the external one) is not checked
# against this address nor saved: it follows the default.
confirm_domain() {
    local label="$1" domain="$2" ip="$3" persist="$4" default="${5:-}" initial="$2" fallback resolved

    [ -n "$ip" ] || return 0
    fallback="$(printf '%s' "$ip" | tr . -).nip.io"
    if ask; then
        domain="$(zz-prompt "${label} DNS domain (empty = ${fallback})" "$domain")"
    fi
    domain="${domain:-$fallback}"
    if [ -n "$default" ] && [ "$domain" = "$default" ]; then
        zz-log i "${label} DNS: *.${domain} (the external domain, by default)"
        return 0
    fi
    resolved="$(getent hosts "vps-access-check.${domain}" 2>/dev/null | awk '{print $1; exit}' || true)"
    if [ "$resolved" != "$ip" ]; then
        if [ -z "$resolved" ]; then
            zz-log w "*.${domain} does not resolve: create a wildcard A record *.${domain} -> ${ip}."
        else
            zz-log w "*.${domain} resolves to ${resolved}, not ${ip}: point the wildcard A record *.${domain} to ${ip} (a stale record, or a NAT/Elastic IP mismatch)."
        fi
        if ask && [ "$(zz-menu -t "${label}: ${domain} is not ready" "keep=Keep ${domain}" "fallback=Use ${fallback}")" = "fallback" ]; then
            domain="$fallback"
        fi
    fi
    # A fallback nothing custom replaced is not saved: it follows the address if it changes.
    [ "$domain" = "$fallback" ] && [ "$initial" = "$fallback" ] || vps-network "$persist" "$domain"
    zz-log i "${label} DNS: *.${domain} -> ${ip}"
}

# hosts: one line per service, with the domain it is reached on.
hosts() {
    local name vis tab

    tab="$(printf '\t')"
    while IFS="$tab" read -r name vis; do
        [ -z "$name" ] || printf '%s: %s.%s (%s)\n' "$name" "$name" "$(vps-network access-domain "$vis" 2>/dev/null || echo '<no internal address>')" "$vis"
    done <<EOF
$(vps-network visibilities)
EOF
}

# validate_external: SYSTEM_EXTERNAL_DOMAIN (a bare domain, a leading "*." is dropped) is saved for vps-network.
validate_external() {
    local domain

    [ -n "${SYSTEM_EXTERNAL_DOMAIN:-}" ] || return 0
    domain="${SYSTEM_EXTERNAL_DOMAIN#\*.}"
    printf '%s\n' "$domain" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$' ||
        { zz-log e "SYSTEM_EXTERNAL_DOMAIN must be a bare domain like apps.example.com (got '${SYSTEM_EXTERNAL_DOMAIN}')." && exit 1; }
    vps-network set-external-domain "$domain"
}

up() {
    validate_external
    confirm_interface
    confirm_visibility
    confirm_domain External "$(vps-network external-domain)" "$(vps-network public-ip)" set-external-domain
    confirm_domain Internal "$(vps-network internal-domain)" "$(vps-network internal-address)" set-internal-domain "$(vps-network external-domain)"
    zz-log s "Access confirmed:"
    hosts | while IFS= read -r line; do zz-log s "  ${line}"; done
}

down() {
    vps-network unset-access
    zz-log s "Access choices forgotten (visibility back to each step's default)."
}

# domain_line <label> <domain> <ip>: the domain, where it comes from and whether DNS answers.
domain_line() {
    local label="$1" domain="$2" ip="$3" fallback resolved how

    if [ -z "$domain" ]; then
        printf '   %-16s %s\n' "$label" "not available (no address and no domain set)"
        return 0
    fi
    [ -n "$ip" ] || ip="<address unknown>"
    fallback="$(printf '%s' "$ip" | tr . -).nip.io"
    [ "$domain" = "$fallback" ] && how="fallback (nip.io)" || how="custom"
    # the internal domain defaults to the external one, which answers with the public address
    if [ -n "${4:-}" ] && [ "$domain" = "$4" ]; then
        how="default (the external domain)" ip="${5:-$ip}"
    fi
    resolved="$(getent hosts "vps-access-check.${domain}" 2>/dev/null | awk '{print $1; exit}' || true)"
    [ "$resolved" = "$ip" ] && resolved="resolves to ${ip}" || resolved="does NOT resolve to ${ip}"
    printf '   %-16s *.%s - %s, %s\n' "$label" "$domain" "$how" "$resolved"
}

# scope_services <public|internal>: the services of that scope, as "name (host), ...".
scope_services() {
    local name vis tab domain out=""

    tab="$(printf '\t')"
    while IFS="$tab" read -r name vis; do
        [ "$vis" = "$1" ] || continue
        domain="$(vps-network access-domain "$vis" 2>/dev/null || true)"
        out="${out:+$out, }${name} (${name}.${domain:-<no domain yet>})"
    done <<EOF
$(vps-network visibilities)
EOF
    printf '%s' "$out"
}

# local_ports: the private ports (closed to the internet), as "name port, ...".
local_ports() {
    vps-network ports | awk -F'\t' '$3 == "private" { printf "%s%s %s", sep, $1, $2; sep = ", " }'
}

summary() {
    local pub int ext_ip int_ip

    pub="$(scope_services public)"
    int="$(scope_services internal)"
    ext_ip="$(vps-network public-ip || true)"
    int_ip="$(vps-network internal-address || true)"
    vps-network summary-block "Access (each service is public OR internal, never both)" \
        "${pub:+$pub - HTTP/HTTPS 80/443 on ${ext_ip:-<public-ip>}, from the internet}" \
        "${int:+$int - HTTP/HTTPS 80/443 on ${int_ip:-<internal-ip>}, clients of the internal network only (source range $(vps-network internal-range || true))}" \
        "private ports, closed to the internet, on the VPS and its internal address: $(local_ports)" \
        "$(domain_line "External domain:" "$(vps-network external-domain)" "$ext_ip" | sed 's/^   //')" \
        "$(domain_line "Internal domain:" "$(vps-network internal-domain)" "$int_ip" "$(vps-network external-domain)" "$ext_ip" | sed 's/^   //')" \
        "(change: sudo vps-setup --only-vps-access, then re-run the service step)"
}

. zz-step
