#!/bin/sh
# Confirms which services are public (server IP) or internal (Tailscale/Cloudflare
# address), and the DNS domains they are reached on. Env vars: see README.
# A zz-setup step: configured by environment inputs (package.json config.inputs),
# run with up, down or summary as its first argument. The menus only run on a terminal.

set -eu
zz-use zz-colors zz-log zz-menu zz-prompt
# shellcheck disable=SC1091
. zz-colors

# ask: menus only with a terminal to ask on (stdin, else /dev/tty, as zz-prompt reads it)
# and unless VPS_ACCESS_MENU=false.
ask() {
    [ "${VPS_ACCESS_MENU:-true}" = "true" ] && { [ -t 0 ] || (: </dev/tty) 2>/dev/null; }
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
    out="$(zz-menu -t "Visibility (a number cycles public/internal, Enter confirms, q keeps)" -c public,internal "$@")" || return 0
    while IFS== read -r key state; do
        [ -n "$key" ] || continue
        if [ "$state" = "internal" ] && [ -z "$(vps-network internal-address)" ]; then
            zz-log w "[vps-setup] ${key}: no internal address (install vps-tailscale or vps-cloudflare); keeping it public."
            state=public
        fi
        vps-network set-visibility "$key" "$state"
    done <<EOF
$out
EOF
}

# confirm_domain <label> <domain> <ip> <persist command>: ask for the domain (empty or
# unresolved: fall back to <ip>.nip.io, which always resolves), then save it.
confirm_domain() {
    local label="$1" domain="$2" ip="$3" persist="$4" initial="$2" fallback resolved

    [ -n "$ip" ] || return 0
    fallback="$(printf '%s' "$ip" | tr . -).nip.io"
    if ask; then
        domain="$(zz-prompt "${label} DNS domain (empty = ${fallback})" "$domain")"
    fi
    domain="${domain:-$fallback}"
    resolved="$(getent hosts "vps-access-check.${domain}" 2>/dev/null | awk '{print $1; exit}' || true)"
    if [ "$resolved" != "$ip" ]; then
        zz-log w "[vps-setup] *.${domain} does not resolve to ${ip} (got '${resolved:-nothing}')."
        if ask && [ "$(zz-menu -t "${label}: ${domain} is not ready" "keep=Keep ${domain}" "fallback=Use ${fallback}")" = "fallback" ]; then
            domain="$fallback"
        fi
    fi
    # A fallback nothing custom replaced is not saved: it follows the address if it changes.
    [ "$domain" = "$fallback" ] && [ "$initial" = "$fallback" ] || vps-network "$persist" "$domain"
    zz-log i "[vps-setup] ${label} DNS: *.${domain} -> ${ip}"
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

up() {
    confirm_visibility
    confirm_domain External "$(vps-network external-domain)" "$(vps-network public-ip)" set-external-domain
    confirm_domain Internal "$(vps-network internal-domain)" "$(vps-network internal-address)" set-internal-domain
    zz-log s "[vps-setup] Access confirmed:"
    hosts | while IFS= read -r line; do zz-log s "[vps-setup]   ${line}"; done
}

down() {
    vps-network unset-access
    zz-log s "[vps-setup] Access choices forgotten (visibility back to each step's default)."
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
        "$(domain_line "Internal domain:" "$(vps-network internal-domain)" "$int_ip" | sed 's/^   //')" \
        "(change: sudo vps-setup --only-vps-access, then re-run the service step)"
}

case "${1:-}" in
    up | down) "$1" ;;
    summary) if command -v summary >/dev/null 2>&1; then summary; fi ;;
    *) zz-log e "Usage: $0 up|down|summary" && exit 1 ;;
esac
