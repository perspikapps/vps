#!/bin/sh
# k3s, kubectl, helm, and Traefik as public ingress. Env vars: see README.

set -eu
# Source the vps-common of this checkout (always the version of the step); a step
# installed on its own gets the one zz-use fetches.
common="$(dirname "$0")/../vps-common/run.sh"
if [ ! -f "$common" ]; then
    zz-use "perspikapps/vps/vps-common@${ZZ_SETUP_REF:-main}"
    common="$(command -v vps-common)"
fi
# shellcheck disable=SC1090
. "$common"

up() {
    local service_file=/etc/systemd/system/k3s.service need_install=1 kubeconfig_path=/etc/rancher/k3s/k3s.yaml i

    # --- k3s
    if command_exists k3s; then
        zz-log i "[vps-setup] k3s already installed ($(k3s --version | head -n1))."
        need_install=0
        if [ -f "$service_file" ] && grep -Pzoq -- "(?s)--disable.{0,80}traefik" "$service_file"; then
            zz-log w "[vps-setup] Existing k3s install has Traefik disabled (from an older version of" \
                "this script that ran with --disable traefik) - reinstalling to" \
                "re-enable it as the public ingress..."
            need_install=1
        fi
    fi

    if [ "$need_install" -eq 1 ]; then
        zz-log i "[vps-setup] Installing k3s..."
        INSTALL_K3S_EXEC="server ${K3S_EXTRA_ARGS:-}"
        export INSTALL_K3S_EXEC
        [ -z "${K3S_VERSION:-}" ] || export INSTALL_K3S_VERSION="$K3S_VERSION"
        zz-install -u https://get.k3s.io -x sh k3s
    fi

    systemctl enable --now k3s

    zz-log i "[vps-setup] Waiting for k3s node to become Ready..."
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
    chmod 644 "$kubeconfig_path"
    zz-persist -l -f /etc/profile.d/k3s-kubeconfig.sh "export KUBECONFIG=${kubeconfig_path}"
    chmod 644 /etc/profile.d/k3s-kubeconfig.sh
    export KUBECONFIG="$kubeconfig_path"

    # --- helm
    if command_exists helm; then
        zz-log i "[vps-setup] Helm already installed ($(helm version --short))."
    else
        zz-log i "[vps-setup] Installing Helm..."
        zz-use helm
    fi

    zz-log s "[vps-setup] k3s, kubectl and helm are installed. KUBECONFIG=${kubeconfig_path}"

    # --- Traefik
    TRAEFIK_ACME_EMAIL="${TRAEFIK_ACME_EMAIL:-admin@example.com}"
    TRAEFIK_ACME_STAGING="${TRAEFIK_ACME_STAGING:-true}"
    TRAEFIK_DASHBOARD_PORT="$(net_port traefik_dashboard)"

    if [ "$TRAEFIK_ACME_EMAIL" = "admin@example.com" ]; then
        zz-log w "[vps-setup] TRAEFIK_ACME_EMAIL not set - using a placeholder. Let's Encrypt will" \
            "still issue certs with it, but you won't get expiry/problem notices." \
            "Set TRAEFIK_ACME_EMAIL to a real address you control."
    fi
    if [ "$TRAEFIK_ACME_STAGING" = "true" ]; then
        zz-log w "[vps-setup] TRAEFIK_ACME_STAGING=true (default): Let's Encrypt's staging" \
            "environment issues untrusted certs (browsers will warn) but has no" \
            "rate limit - safe to test against repeatedly. Set" \
            "TRAEFIK_ACME_STAGING=false for real, trusted certs once ready" \
            "(production Let's Encrypt has strict per-domain rate limits, so" \
            "avoid iterating against it)."
    fi

    # Let's Encrypt production unless staging was asked for (see above).
    TRAEFIK_ACME_CASERVER="https://acme-v02.api.letsencrypt.org/directory"
    if [ "$TRAEFIK_ACME_STAGING" = "true" ]; then
        TRAEFIK_ACME_CASERVER="https://acme-staging-v02.api.letsencrypt.org/directory"
    fi

    zz-log i "[vps-setup] Configuring Traefik (public ingress on 80/443, Let's Encrypt, dashboard on ${TRAEFIK_DASHBOARD_PORT})..."
    yaml-render "$(dirname "$0")/helm/traefik-config.yaml" TRAEFIK_DASHBOARD_PORT="$TRAEFIK_DASHBOARD_PORT" TRAEFIK_ACME_EMAIL="$TRAEFIK_ACME_EMAIL" TRAEFIK_ACME_CASERVER="$TRAEFIK_ACME_CASERVER" | kubectl apply -f -

    zz-log i "[vps-setup] Waiting for k3s's helm-controller to apply the Traefik config (creates/updates the job)..."
    for i in $(seq 1 30); do
        kubectl -n kube-system get deploy traefik >/dev/null 2>&1 && break
        sleep 5
    done
    kube-progress kube-system "Traefik rollout" kubectl -n kube-system rollout status deploy/traefik --timeout=5m ||
        zz-log w "[vps-setup] Traefik didn't report ready in time - check: kubectl -n kube-system get pods -l app.kubernetes.io/name=traefik"

    reapply_private_guard

    zz-log s "[vps-setup] Traefik configured: HTTP/HTTPS public on 80/443, dashboard on ${TRAEFIK_DASHBOARD_PORT} (private access only)."
}

down() {
    if [ -x /usr/local/bin/k3s-uninstall.sh ]; then
        zz-log i "[vps-setup] Uninstalling k3s (this also removes everything deployed on it: Rancher, any Marketplace-installed apps, etc.)..."
        /usr/local/bin/k3s-uninstall.sh
    else
        zz-log w "[vps-setup] k3s uninstall script not found (/usr/local/bin/k3s-uninstall.sh); k3s may not be installed."
    fi
    rm -f /usr/local/bin/kubectl /etc/profile.d/k3s-kubeconfig.sh
    zz-log s "[vps-setup] k3s removed."
}

summary() {
    local host

    host="$(public_ip)"
    cat <<EOF
 Traefik (k3s):       public: http://${host:-<public-ip>} and https://${host:-<public-ip>}
                       (a "letsencrypt" certResolver is configured and
                       ready to use - it won't issue anything until you
                       add the router.tls.certresolver annotation to your
                       own Ingress; see README)
                       dashboard: http://$(summary_host):$(net_port traefik_dashboard)/dashboard/
                       (private access only, no login - see README's Security model)

 kubectl / helm:      KUBECONFIG=/etc/rancher/k3s/k3s.yaml (already exported
                       via /etc/profile.d/k3s-kubeconfig.sh for new shells)
EOF
}

. zz-step
