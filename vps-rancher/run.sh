#!/bin/sh
# Rancher on k3s. Env vars: see README.
# A zz-setup step: configured by environment inputs (package.json config.inputs),
# so there is no zz-args block; run with up, down or summary as its first argument.

set -eu
zz-use zz-colors zz-log zz-persist yaml-render kube-progress kube-diagnose kube-teardown kube-service-port
# shellcheck disable=SC1091
. zz-colors
# Scripts of this checkout, called (never sourced): addresses, private interface, ports.
vps_network="$(dirname "$0")/../vps-network/run.sh"
vps_cert_manager="$(dirname "$0")/../vps-cert-manager/run.sh"

up() {
    local http_port https_port ingress_host host password values_file chart_version dir rc=0

    export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
    dir="$(cd "$(dirname "$0")" && pwd)"
    command -v kubectl >/dev/null 2>&1 || { zz-log e "[vps-setup] kubectl not found; run vps-k3s/run.sh first." && exit 1; }
    command -v helm >/dev/null 2>&1 || { zz-log e "[vps-setup] helm not found; run vps-k3s/run.sh first." && exit 1; }

    # --- parameters: ports, public dashboard host, server URL, bootstrap password
    http_port="$("$vps_network" port rancher_http)"
    https_port="$("$vps_network" port rancher_https)"
    # Public dashboard host (Traefik, same domain source as Coder): rancher.<wildcard domain>.
    # RANCHER_INGRESS=false keeps Rancher private-only (ufw-guarded ports). Public or
    # private, never both: the private ports are only bound when there is no public host.
    ingress_host=""
    if [ "${RANCHER_INGRESS:-true}" = "true" ]; then
        ingress_host="${RANCHER_INGRESS_HOST:-rancher.$("$vps_network" wildcard-domain)}"
        case "$ingress_host" in
            *[!A-Za-z0-9.-]*) zz-log e "[vps-setup] RANCHER_INGRESS_HOST must be a host name (got '${ingress_host}')." && exit 1 ;;
        esac
        [ "$ingress_host" != "rancher." ] || { zz-log e "[vps-setup] No Rancher host: set RANCHER_INGRESS_HOST or WILDCARD_DOMAIN." && exit 1; }
    fi
    # Rancher's server URL follows the public host; without one, the private address.
    host="${RANCHER_HOSTNAME:-${ingress_host:-$("$vps_network" private-address)}}"
    host="${host:-$(hostname -I | awk '{print $1}')}"

    password="$(zz-persist -f "$VPS_SECRETS_FILE" -s -g 24 RANCHER_BOOTSTRAP_PASSWORD "${RANCHER_BOOTSTRAP_PASSWORD:-}")"

    # --- chart repositories
    # The community "latest" channel by default; RANCHER_CHART_REPO_URL selects
    # another, e.g. SUSE Rancher Prime (https://charts.rancher.com/server-charts/prime).
    # --force-update lets a changed URL replace the alias from a previous run.
    RANCHER_CHART_REPO_URL="${RANCHER_CHART_REPO_URL:-https://releases.rancher.com/server-charts/latest}"
    case "$RANCHER_CHART_REPO_URL" in
        http://* | https://*) ;;
        *) zz-log e "[vps-setup] RANCHER_CHART_REPO_URL must be an http(s) Helm repository URL (got '${RANCHER_CHART_REPO_URL}')." && exit 1 ;;
    esac
    zz-log i "[vps-setup] Using the Rancher chart repository ${RANCHER_CHART_REPO_URL}"
    helm repo add vps-rancher "$RANCHER_CHART_REPO_URL" --force-update >/dev/null ||
        { zz-log e "[vps-setup] Could not add the Helm repository ${RANCHER_CHART_REPO_URL}." && exit 1; }
    helm repo update vps-rancher >/dev/null ||
        { zz-log e "[vps-setup] Could not fetch the chart index from ${RANCHER_CHART_REPO_URL} (check the URL and any access it needs)." && exit 1; }

    # Bitnami charts (e.g. the databases some Marketplace apps depend on) resolve from this alias.
    helm repo add bitnami https://charts.bitnami.com/bitnami --force-update >/dev/null ||
        { zz-log e "[vps-setup] Could not add the Helm repository https://charts.bitnami.com/bitnami." && exit 1; }

    "$vps_cert_manager"

    kubectl create namespace cattle-system --dry-run=client -o yaml | kubectl apply -f -

    # --- Rancher release
    # shortcut: the unquoted version splits on spaces, a chart version has none.
    chart_version="${RANCHER_CHART_VERSION:+--version ${RANCHER_CHART_VERSION}}"

    zz-log i "[vps-setup] Installing/upgrading Rancher (hostname=${host}); this usually takes 3-8 minutes (images are pulled), status every ${PROGRESS_INTERVAL:-15}s..."
    # hostname and bootstrapPassword go through a values file with JSON-quoted
    # strings, not --set: helm parses --set bootstrapPassword=12345678 as an
    # integer and the chart's b64enc then fails ("wrong type for value; expected
    # string; got int64"); --set also splits on commas and shows in `ps`.
    values_file="$(mktemp)"
    jq -n --arg hostname "$host" --arg bootstrapPassword "$password" \
        --arg svc "$([ -n "$ingress_host" ] && echo ClusterIP || echo LoadBalancer)" \
        '{hostname: $hostname, bootstrapPassword: $bootstrapPassword, service: {type: $svc}}' >"$values_file"
    # No --wait here: helm would wait for the LoadBalancer Service to get an
    # address, but k3s's ServiceLB cannot place it while Traefik holds host ports
    # 80/443, and it is the rebind below that frees them - waiting first deadlocks
    # ("UPGRADE FAILED: context deadline exceeded"). The rollout wait below does
    # the waiting, once the Service is on its own ports.
    # A re-run finds the Service already rebound (7080/7083 below): helm would merge
    # the chart's 80/http and 443/https into it and the API rejects the duplicate
    # port names ("spec.ports[2].name: Duplicate value: http"). Remove it so helm
    # recreates it from the chart; it is rebound again right after. Pods keep running.
    if kubectl -n cattle-system get service rancher >/dev/null 2>&1; then
        zz-log i "[vps-setup] Removing the already-rebound rancher Service so helm can recreate it (rebound again below)..."
        kubectl -n cattle-system delete service rancher --wait=true
    fi

    # shellcheck disable=SC2086
    kube-progress cattle-system "Rancher install" \
        helm upgrade --install rancher vps-rancher/rancher \
        --namespace cattle-system \
        --values "${dir}/helm/values.yaml" \
        --values "$values_file" \
        $chart_version \
        --timeout 10m || rc=$?
    rm -f "$values_file"
    if [ "$rc" -ne 0 ]; then
        kube-diagnose cattle-system
        exit "$rc"
    fi

    # --- private ports and rollout
    if [ -z "$ingress_host" ]; then
        zz-log i "[vps-setup] Rebinding the rancher Service to ports ${http_port}/${https_port}..."
        kube-service-port cattle-system rancher http "$http_port" || true
        kube-service-port cattle-system rancher https "$https_port" || true
    fi

    zz-log i "[vps-setup] Waiting for Rancher pods to be ready..."
    if ! kube-progress cattle-system "Rancher rollout" kubectl -n cattle-system rollout status deploy/rancher --timeout=10m; then
        kube-diagnose cattle-system
        zz-log e "[vps-setup] Rancher did not become ready in time (see the diagnostics above); re-run: sudo vps-setup --only-vps-rancher" && exit 1
    fi

    # --- public dashboard, through k3s's Traefik (see ingress.yaml)
    if [ -n "$ingress_host" ]; then
        zz-log i "[vps-setup] Exposing Rancher through Traefik at ${ingress_host}..."
        yaml-render "${dir}/helm/ingress.yaml" INGRESS_HOST="$ingress_host" | kubectl apply -f -
    else
        kubectl -n cattle-system delete ingress rancher-traefik --ignore-not-found
    fi

    "$vps_network" reapply-guard

    zz-log s "[vps-setup] Rancher installed."
    [ -z "$ingress_host" ] || zz-log s "[vps-setup] UI: https://${ingress_host} (via Traefik, public)"
    [ -n "$ingress_host" ] || zz-log s "[vps-setup] UI (private): https://$("$vps_network" summary-host):${https_port} (also plain-port ${http_port})"
    zz-log s "[vps-setup] Bootstrap password saved to ${VPS_SECRETS_FILE}: ${password}"
}

down() {
    export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
    command -v kubectl >/dev/null 2>&1 || { zz-log w "[vps-setup] kubectl not found; nothing to remove." && return 0; }
    kube-teardown cattle-system rancher
    zz-persist -q -f "$VPS_SECRETS_FILE" -u RANCHER_BOOTSTRAP_PASSWORD
    zz-log s "[vps-setup] Rancher removed."
}

summary() {
    cat <<EOF
 Rancher:             $(kubectl -n cattle-system get ingress rancher-traefik -o jsonpath='https://{.spec.rules[0].host} (through Traefik - public)' 2>/dev/null || echo "private: https://$("$vps_network" summary-host):$("$vps_network" port rancher_https) (also on plain port $("$vps_network" port rancher_http))")
                       user:     admin
                       password: $(zz-persist -f "$VPS_SECRETS_FILE" -r RANCHER_BOOTSTRAP_PASSWORD | grep . || echo 'not set - run vps-rancher/run.sh')
                       (saved to ${VPS_SECRETS_FILE}; you'll
                       be prompted to change it on first login)
EOF
}

case "${1:-}" in
    up | down) "$1" ;;
    summary) if command -v summary >/dev/null 2>&1; then summary; fi ;;
    *) zz-log e "Usage: $0 up|down|summary" && exit 1 ;;
esac
