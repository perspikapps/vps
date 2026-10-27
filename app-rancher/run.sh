#!/bin/sh
# Rancher on k3s. Env vars: see README.
# A zz-setup step: configured by environment inputs (package.json config.inputs),
# so there is no zz-args block; run with up, down or summary as its first argument.

set -eu
zz-use zz-colors zz-log zz-persist kube-apply kube-require kube-rollout kube-teardown helm-repo helm-install
# shellcheck disable=SC1091
. zz-colors
app_cert_manager="$(dirname "$0")/../app-cert-manager/run.sh"

up() {
    local ingress_host host password values_file chart_version dir access middlewares certresolver

    eval "$(kube-require)"
    dir="$(cd "$(dirname "$0")" && pwd)"

    # --- parameters: dashboard host, server URL, bootstrap password
    # Rancher is only reached through Traefik, at rancher.<domain>: the route (public or internal,
    # never both) and the domain come from the system config (vps-access), not from this step.
    # Both are Traefik 80/443: public has Let's Encrypt; internal is a host on the internal domain
    # behind the internal-only middleware (internal network clients only, default certificate).
    eval "$(vps-network access-route rancher)"
    access="$route_access" middlewares="$route_middlewares" certresolver="$route_certresolver"
    [ -n "$route_domain" ] || { zz-log e "No domain for Rancher: set SYSTEM_EXTERNAL_DOMAIN / SYSTEM_INTERNAL_DOMAIN (or install a network)." && exit 1; }
    ingress_host="rancher.${route_domain}"
    # Rancher's server URL is that host.
    host="$ingress_host"

    password="$(zz-persist -S -g 24 RANCHER_BOOTSTRAP_PASSWORD "${RANCHER_BOOTSTRAP_PASSWORD:-}")"

    # --- chart repositories
    # The community "latest" channel by default; RANCHER_CHART_REPO_URL selects
    # another, e.g. SUSE Rancher Prime (https://charts.rancher.com/server-charts/prime).
    # Bitnami charts (e.g. the databases some apps depend on) resolve from their alias.
    RANCHER_CHART_REPO_URL="${RANCHER_CHART_REPO_URL:-https://releases.rancher.com/server-charts/latest}"
    zz-log i "Using the Rancher chart repository ${RANCHER_CHART_REPO_URL}"
    helm-repo app-rancher "$RANCHER_CHART_REPO_URL" bitnami https://charts.bitnami.com/bitnami

    "$app_cert_manager"

    # --- Rancher release
    # shortcut: the unquoted version splits on spaces, a chart version has none.
    chart_version="${RANCHER_CHART_VERSION:+--version ${RANCHER_CHART_VERSION}}"

    zz-log i "Installing/upgrading Rancher (hostname=${host}); this usually takes 3-8 minutes (images are pulled), status every ${PROGRESS_INTERVAL:-15}s..."
    # hostname and bootstrapPassword go through a values file with JSON-quoted
    # strings, not --set: helm parses --set bootstrapPassword=12345678 as an
    # integer and the chart's b64enc then fails ("wrong type for value; expected
    # string; got int64"); --set also splits on commas and shows in `ps`.
    values_file="$(mktemp)"
    jq -n --arg hostname "$host" --arg bootstrapPassword "$password" \
        '{hostname: $hostname, bootstrapPassword: $bootstrapPassword}' >"$values_file"
    # A Service an older run rebound to private ports (7080/7083) would merge with the
    # chart's ports and the API rejects the duplicate names: remove it so helm recreates
    # it as ClusterIP. Pods keep running.
    if kubectl -n cattle-system get service rancher -o jsonpath='{.spec.type}' 2>/dev/null | grep -q LoadBalancer; then
        zz-log i "Removing the old LoadBalancer rancher Service so helm can recreate it..."
        kubectl -n cattle-system delete service rancher --wait=true
    fi
    # No --wait: the rollout wait below does the waiting, with progress.
    # shellcheck disable=SC2086
    helm-install cattle-system rancher app-rancher/rancher \
        --values "${dir}/helm/values.yaml" \
        --values "$values_file" \
        $chart_version || { rm -f "$values_file" && exit 1; }
    rm -f "$values_file"

    # --- rollout
    zz-log i "Waiting for Rancher pods to be ready..."
    kube-rollout -t 10m cattle-system rancher ||
        { zz-log e "Re-run: sudo vps-setup --only-app-rancher" && exit 1; }

    # --- dashboard route, through k3s's Traefik (see ingress.yaml)
    zz-log i "Exposing Rancher through Traefik at ${ingress_host} (${access})..."
    kube-apply "${dir}/helm/ingress.yaml" INGRESS_HOST="$ingress_host" MIDDLEWARES="$middlewares" HTTP_MIDDLEWARES="${middlewares:+$middlewares,}kube-system-redirect-https@kubernetescrd" CERTRESOLVER="$certresolver"

    zz-log s "Rancher installed."
    zz-log s "UI: https://${ingress_host} (via Traefik, ${access})"
    zz-log s "Bootstrap password saved to ${ZZ_SECRETS_FILE}: ${password}"
}

down() {
    eval "$(kube-require -d)"
    kube-teardown cattle-system rancher
    zz-persist -S -q -u RANCHER_BOOTSTRAP_PASSWORD
    zz-log s "Rancher removed."
}

summary() {
    local host access pub="" int=""

    host="$(kubectl -n cattle-system get ingress rancher-traefik -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || true)"
    access="$(vps-network visibility rancher)"
    if [ -z "$host" ]; then
        pub="no route yet: run app-rancher/run.sh"
    elif [ "$access" = "internal" ]; then
        int="https://${host} (internal network clients only; Traefik's default certificate)"
    else
        pub="https://${host} (Let's Encrypt)"
    fi
    vps-network summary-block Rancher "$pub" "$int" "none: a ClusterIP; kubectl -n cattle-system port-forward svc/rancher 8443:443" \
        "user:     admin" \
        "password: $(zz-persist -S -r -v 'not set - run app-rancher/run.sh' RANCHER_BOOTSTRAP_PASSWORD)" \
        "(saved to ${ZZ_SECRETS_FILE}; you'll be prompted to change it on first login)"
}

case "${1:-}" in
    up | down) "$1" ;;
    summary) if command -v summary >/dev/null 2>&1; then summary; fi ;;
    *) zz-log e "Usage: $0 up|down|summary" && exit 1 ;;
esac
