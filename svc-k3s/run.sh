#!/bin/sh
# k3s, kubectl, helm, and Traefik as public ingress. Env vars: see README.

set -eu
export DEBIAN_FRONTEND=noninteractive
zz-use zz-colors zz-log zz-persist zz-install kube-apply kube-rollout systemd-service kube-progress kube-diagnose yaml-render zz-step
# shellcheck disable=SC1091
. zz-colors

up() {
    local service_file=/etc/systemd/system/k3s.service need_install=1 kubeconfig_path=/etc/rancher/k3s/k3s.yaml i

    # --- k3s
    if command -v k3s >/dev/null 2>&1; then
        zz-log i "k3s already installed ($(k3s --version | head -n1))."
        need_install=0
        if [ -f "$service_file" ] && grep -Pzoq -- "(?s)--disable.{0,80}traefik" "$service_file"; then
            zz-log w "Existing k3s install has Traefik disabled (from an older version of" \
                "this script that ran with --disable traefik) - reinstalling to" \
                "re-enable it as the public ingress..."
            need_install=1
        fi
    fi

    if [ "$need_install" -eq 1 ]; then
        zz-log i "Installing k3s..."
        INSTALL_K3S_EXEC="server ${K3S_EXTRA_ARGS:-}"
        export INSTALL_K3S_EXEC
        [ -z "${K3S_VERSION:-}" ] || export INSTALL_K3S_VERSION="$K3S_VERSION"
        zz-install -u https://get.k3s.io -x sh k3s
    fi

    systemd-service up k3s

    zz-log i "Waiting for k3s node to become Ready..."
    for i in $(seq 1 30); do
        if k3s kubectl get nodes 2>/dev/null | grep -q ' Ready'; then
            break
        fi
        sleep 5
    done
    k3s kubectl get nodes

    if [ ! -e /usr/local/bin/kubectl ]; then
        ln -s "$(command -v k3s)" /usr/local/bin/kubectl
    fi

    mkdir -p /etc/rancher/k3s
    # owner-only: the admin credentials of the cluster (k3s default; the steps run as root)
    chmod 600 "$kubeconfig_path"
    zz-persist -l -f /etc/profile.d/k3s-kubeconfig.sh "export KUBECONFIG=${kubeconfig_path}"
    chmod 644 /etc/profile.d/k3s-kubeconfig.sh
    export KUBECONFIG="$kubeconfig_path"

    # --- helm
    if command -v helm >/dev/null 2>&1; then
        zz-log i "Helm already installed ($(helm version --short))."
    else
        zz-log i "Installing Helm..."
        zz-use helm
    fi

    zz-log s "k3s, kubectl and helm are installed. KUBECONFIG=${kubeconfig_path}"

    # --- Traefik
    K3S_TRAEFIK_ACME_EMAIL="${K3S_TRAEFIK_ACME_EMAIL:-admin@example.com}"
    K3S_TRAEFIK_ACME_STAGING="${K3S_TRAEFIK_ACME_STAGING:-true}"
    K3S_TRAEFIK_DASHBOARD_PORT="$(vps-network port k3s_traefik_dashboard)"

    if [ "$K3S_TRAEFIK_ACME_EMAIL" = "admin@example.com" ]; then
        zz-log w "K3S_TRAEFIK_ACME_EMAIL not set - using a placeholder. Let's Encrypt will" \
            "still issue certs with it, but you won't get expiry/problem notices." \
            "Set K3S_TRAEFIK_ACME_EMAIL to a real address you control."
    fi
    if [ "$K3S_TRAEFIK_ACME_STAGING" = "true" ]; then
        zz-log w "K3S_TRAEFIK_ACME_STAGING=true (default): Let's Encrypt's staging" \
            "environment issues untrusted certs (browsers will warn) but has no" \
            "rate limit - safe to test against repeatedly. Set" \
            "K3S_TRAEFIK_ACME_STAGING=false for real, trusted certs once ready" \
            "(production Let's Encrypt has strict per-domain rate limits, so" \
            "avoid iterating against it)."
    fi

    # Let's Encrypt production unless staging was asked for (see above).
    TRAEFIK_ACME_CASERVER="https://acme-v02.api.letsencrypt.org/directory"
    if [ "$K3S_TRAEFIK_ACME_STAGING" = "true" ]; then
        TRAEFIK_ACME_CASERVER="https://acme-staging-v02.api.letsencrypt.org/directory"
    fi

    zz-log i "Configuring Traefik (public ingress on 80/443, Let's Encrypt, dashboard on ${K3S_TRAEFIK_DASHBOARD_PORT})..."
    kube-apply "$(dirname "$0")/helm/traefik-config.yaml" K3S_TRAEFIK_DASHBOARD_PORT="$K3S_TRAEFIK_DASHBOARD_PORT" K3S_TRAEFIK_ACME_EMAIL="$K3S_TRAEFIK_ACME_EMAIL" TRAEFIK_ACME_CASERVER="$TRAEFIK_ACME_CASERVER"

    zz-log i "Waiting for k3s's helm-controller to apply the Traefik config (creates/updates the job)..."
    for i in $(seq 1 30); do
        kubectl -n kube-system get deploy traefik >/dev/null 2>&1 && break
        sleep 5
    done
    kube-rollout -w kube-system traefik

    kubectl apply -f "$(dirname "$0")/helm/redirect-middleware.yaml" ||
        zz-log w "Could not create the redirect-https middleware (Traefik CRDs not ready?): re-run svc-k3s."

    # The middleware every internal route uses: only the internal network's clients get through.
    INTERNAL_RANGE="$(vps-network internal-range | sed 's/[^,][^,]*/"&"/g; s/,/, /g')"
    if [ -n "$INTERNAL_RANGE" ]; then
        kube-apply "$(dirname "$0")/helm/internal-middleware.yaml" INTERNAL_RANGE="$INTERNAL_RANGE" ||
            zz-log w "Could not create the internal-only middleware (Traefik CRDs not ready?): re-run svc-k3s."
    else
        zz-log w "No internal network yet: internal routes would have no source limit, so none is created (run svc-tailscale or svc-cloudflare, then re-run svc-k3s)."
    fi

    vps-network reapply-guard

    zz-log s "Traefik configured: HTTP/HTTPS public on 80/443, dashboard on ${K3S_TRAEFIK_DASHBOARD_PORT} (private access only)."
}

down() {
    if [ -x /usr/local/bin/k3s-uninstall.sh ]; then
        zz-log i "Uninstalling k3s (this also removes everything deployed on it: Rancher, the app-* apps, etc.)..."
        /usr/local/bin/k3s-uninstall.sh
    else
        zz-log w "k3s uninstall script not found (/usr/local/bin/k3s-uninstall.sh); k3s may not be installed."
    fi
    rm -f /usr/local/bin/kubectl /etc/profile.d/k3s-kubeconfig.sh
    zz-log s "k3s removed."
}

summary() {
    local host

    host="$(vps-network public-ip)"
    vps-network summary-block "Traefik (k3s)" \
        "http://${host:-<public-ip>} and https://${host:-<public-ip>} (web/websecure, 80/443; Let's Encrypt resolver \"letsencrypt\")" \
        "the same 80/443 on $(vps-network summary-host), for internal hosts only (internal-only middleware: sources $(vps-network internal-range || true))" \
        "dashboard http://localhost:$(vps-network port k3s_traefik_dashboard)/dashboard/ (on the VPS, no login; also on the internal address)" \
        "A \"letsencrypt\" certResolver is ready: it issues nothing until your Ingress has the router.tls.certresolver annotation (see README)." \
        "kubectl / helm: KUBECONFIG=/etc/rancher/k3s/k3s.yaml (exported via /etc/profile.d/k3s-kubeconfig.sh for new shells)"
}

. zz-step
