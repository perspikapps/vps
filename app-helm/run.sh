#!/bin/sh
# app-helm up|down|summary <app> [options] [helm args...] - installs charts/<app> of this
# checkout with helm (a script shared by the app-* steps, not a step). Options:
#   --middlewares-key <dotted.path>   the chart value that takes the Traefik middlewares of the route (set for internal)
#   --note <text>                a line added to the summary (repeatable)
# Every other argument goes to `helm upgrade --install` (e.g. --set, --values).

set -eu
zz-use zz-colors zz-log kube-require helm-install kube-teardown
# shellcheck disable=SC1091
. zz-colors

if [ "$#" -lt 2 ]; then
    zz-log e "Usage: app-helm up|down|summary <app> [--middlewares-key <path>] [--note <text>] [helm args...]"
    exit 1
fi
action="$1" app="$2"
shift 2
middlewares_key="" notes=""
rest=""
# Options are split from the helm arguments; the helm ones are kept quoted in "$@".
n=$#
while [ "$n" -gt 0 ]; do
    arg="$1"
    shift
    n=$((n - 1))
    case "$arg" in
        --middlewares-key) middlewares_key="$1" && shift && n=$((n - 1)) ;;
        --note) notes="${notes}${1}
" && shift && n=$((n - 1)) ;;
        *) set -- "$@" "$arg"; rest=1 ;;
    esac
done

root="${ZZ_SETUP_ROOT:-${VPS_SETUP_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}}"
chart="$root/charts/$app"
ns="${APP_NAMESPACE:-$app}"

up() {
    local access domain values

    eval "$(kube-require)"
    [ -f "$chart/Chart.yaml" ] || { zz-log e "No chart at ${chart}." && exit 1; }

    eval "$(vps-network access-route "$app")"
    access="$route_access" domain="$route_domain"
    [ -n "$domain" ] || { zz-log e "No ${access} domain for ${app}: set SYSTEM_EXTERNAL_DOMAIN / SYSTEM_INTERNAL_DOMAIN (or install a network)." && exit 1; }

    # the shared domain (apps are <app>.<domain>) and, where the chart takes one, the route middlewares
    values="$(mktemp)"
    jq -n --arg d "$domain" --arg m "$route_middlewares" --arg k "$middlewares_key" \
        '{global: {domain: $d}} | if $k != "" and $m != "" then setpath($k | split("."); $m) else . end' >"$values"

    zz-log i "Installing ${app} (${access}, *.${domain}) from ${chart}..."
    helm dependency update "$chart" >/dev/null ||
        { rm -f "$values" && zz-log e "Could not fetch the dependencies of ${app}." && exit 1; }
    helm-install "$ns" "$app" "$chart" --values "$values" "$@" || { rm -f "$values" && exit 1; }
    rm -f "$values"
    zz-log s "${app} installed in namespace ${ns}."
}

down() {
    eval "$(kube-require -d)"
    kube-teardown "$ns" "$app"
    zz-log s "${app} removed."
}

summary() {
    local host access url note pub="" int=""

    command -v kubectl >/dev/null 2>&1 && kubectl get namespace "$ns" >/dev/null 2>&1 || return 0
    host="$(kubectl -n "$ns" get ingress -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || true)"
    access="$(vps-network visibility "$app")"
    if [ -z "$host" ]; then
        pub="no ingress found in namespace ${ns}"
    else
        url="http://${host}"
        if [ "$access" = "internal" ]; then int="${url} (80/443, internal network clients only)"; else pub="${url} (through Traefik, 80/443)"; fi
    fi
    set --
    while IFS= read -r note; do
        [ -z "$note" ] || set -- "$@" "$note"
    done <<EOF
$notes
EOF
    vps-network summary-block "$app" "$pub" "$int" - "$@"
}

case "$action" in
    up) up "$@" ;;
    down) down ;;
    summary) summary ;;
    *) zz-log e "Usage: app-helm up|down|summary <app> ..." && exit 1 ;;
esac
