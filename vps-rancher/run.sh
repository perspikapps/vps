#!/bin/sh
# Rancher on k3s. Env vars: see README.
# A zz-setup step: configured by environment inputs (package.json config.inputs),
# so there is no zz-args block; vps-common's dispatch_action runs up, down or summary.

set -eu
zz-use "perspikapps/vps/vps-common@${ZZ_SETUP_REF:-main}" zz-persist
# vps-common comes from zz-use's download cache (24h for a branch). A copy from before
# the POSIX sh rewrite breaks under sh ("trap: ERR: bad trap"): refresh it when stale.
grep -q '^report_exit()' "$(command -v vps-common)" 2>/dev/null || zz-use --force "perspikapps/vps/vps-common@${ZZ_SETUP_REF:-main}"
# shellcheck disable=SC1091
. vps-common
# vps-common comes from zz-use's download cache (24h for a branch), while the
# steps come from the fresh checkout: an older cached copy lacks newer helpers.
command -v reapply_private_guard >/dev/null || {
    zz-log e "[vps-setup] The cached vps-common is older than this step. Refresh it and re-run:" \
        "sudo zz-use --force perspikapps/vps/vps-common" && exit 1
}

up() {
    local http_port https_port ingress_host host password values_file chart_version dir rc=0

    export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
    dir="$(cd "$(dirname "$0")" && pwd)"
    command_exists kubectl || { zz-log e "[vps-setup] kubectl not found; run vps-k3s/run.sh first." && exit 1; }
    command_exists helm || { zz-log e "[vps-setup] helm not found; run vps-k3s/run.sh first." && exit 1; }

    # --- parameters: ports, public dashboard host, server URL, bootstrap password
    http_port="$(net_port rancher_http)"
    https_port="$(net_port rancher_https)"
    # Public dashboard host (Traefik, same domain source as Coder): rancher.<wildcard domain>.
    # RANCHER_INGRESS=false keeps Rancher private-only (ufw-guarded ports).
    ingress_host=""
    if [ "${RANCHER_INGRESS:-true}" = "true" ]; then
        ingress_host="${RANCHER_INGRESS_HOST:-rancher.$(wildcard_domain)}"
        case "$ingress_host" in
            *[!A-Za-z0-9.-]*) zz-log e "[vps-setup] RANCHER_INGRESS_HOST must be a host name (got '${ingress_host}')." && exit 1 ;;
        esac
        [ "$ingress_host" != "rancher." ] || { zz-log e "[vps-setup] No Rancher host: set RANCHER_INGRESS_HOST or WILDCARD_DOMAIN." && exit 1; }
    fi
    # Rancher's server URL follows the public host; without one, the private address.
    host="${RANCHER_HOSTNAME:-${ingress_host:-$(private_address)}}"
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

    ensure_cert_manager

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
        '{hostname: $hostname, bootstrapPassword: $bootstrapPassword}' >"$values_file"
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
    run_with_progress cattle-system "Rancher install" \
        helm upgrade --install rancher vps-rancher/rancher \
        --namespace cattle-system \
        --values "${dir}/helm/values.yaml" \
        --values "$values_file" \
        $chart_version \
        --timeout 10m || rc=$?
    rm -f "$values_file"
    if [ "$rc" -ne 0 ]; then
        dump_diagnostics cattle-system
        exit "$rc"
    fi

    # --- private ports and rollout
    zz-log i "[vps-setup] Rebinding the rancher Service to ports ${http_port}/${https_port}..."
    patch_service_port cattle-system rancher http "$http_port" || true
    patch_service_port cattle-system rancher https "$https_port" || true

    zz-log i "[vps-setup] Waiting for Rancher pods to be ready..."
    if ! run_with_progress cattle-system "Rancher rollout" kubectl -n cattle-system rollout status deploy/rancher --timeout=10m; then
        dump_diagnostics cattle-system
        zz-log e "[vps-setup] Rancher did not become ready in time (see the diagnostics above); re-run: sudo vps-setup --only-vps-rancher" && exit 1
    fi

    # --- public dashboard, through k3s's Traefik (see ingress.yaml)
    if [ -n "$ingress_host" ]; then
        zz-log i "[vps-setup] Exposing Rancher through Traefik at ${ingress_host}..."
        yaml-render "${dir}/helm/ingress.yaml" INGRESS_HOST="$ingress_host" | kubectl apply -f -
    else
        kubectl -n cattle-system delete ingress rancher-traefik --ignore-not-found
    fi

    reapply_private_guard

    zz-log s "[vps-setup] Rancher installed."
    [ -z "$ingress_host" ] || zz-log s "[vps-setup] UI: https://${ingress_host} (via Traefik, public)"
    zz-log s "[vps-setup] UI (private): https://$(summary_host):${https_port} (also plain-port ${http_port})"
    zz-log s "[vps-setup] Bootstrap password saved to ${VPS_SECRETS_FILE}: ${password}"
}

down() {
    export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
    command_exists kubectl || { zz-log w "[vps-setup] kubectl not found; nothing to remove." && return 0; }
    helm_teardown cattle-system rancher
    zz-persist -q -f "$VPS_SECRETS_FILE" -u RANCHER_BOOTSTRAP_PASSWORD
    zz-log s "[vps-setup] Rancher removed."
}

summary() {
    cat <<EOF
 Rancher:             $(kubectl -n cattle-system get ingress rancher-traefik -o jsonpath='https://{.spec.rules[0].host} (through Traefik - public)' 2>/dev/null || echo '(no public route)')
                       private: https://$(summary_host):$(net_port rancher_https)
                       (also on plain port $(net_port rancher_http))
                       user:     admin
                       password: $(zz-persist -f "$VPS_SECRETS_FILE" -r RANCHER_BOOTSTRAP_PASSWORD | grep . || echo 'not set - run vps-rancher/run.sh')
                       (saved to ${VPS_SECRETS_FILE}; you'll
                       be prompted to change it on first login)
EOF
}

dispatch_action "$@"
