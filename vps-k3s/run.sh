#!/usr/bin/env bash
# k3s, kubectl, helm, and Traefik as public ingress. Env vars: see README.

set -euo pipefail
command -v zz_use >/dev/null 2>&1 || { echo "zz_use not found on PATH - run this repo's setup.sh first: curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/setup.sh | sh" >&2; exit 1; }
zz_use "perspikapps/vps/vps-common@${VPS_SETUP_REPO_REF:-main}"
# shellcheck disable=SC1091
. vps-common

up() {
require_root

K3S_SERVICE_FILE=/etc/systemd/system/k3s.service
NEED_K3S_INSTALL=1
if command_exists k3s; then
  zz_log i "[vps-setup] k3s already installed ($(k3s --version | head -n1))."
  NEED_K3S_INSTALL=0
  if [[ -f "$K3S_SERVICE_FILE" ]] && grep -Pzoq -- "(?s)--disable.{0,80}traefik" "$K3S_SERVICE_FILE"; then
    zz_log w "[vps-setup] Existing k3s install has Traefik disabled (from an older version of" \
         "this script that ran with --disable traefik) - reinstalling to" \
         "re-enable it as the public ingress..."
    NEED_K3S_INSTALL=1
  fi
fi

if [[ "$NEED_K3S_INSTALL" -eq 1 ]]; then
  zz_log i "[vps-setup] Installing k3s..."
  INSTALL_K3S_EXEC="server ${K3S_EXTRA_ARGS:-}"
  export INSTALL_K3S_EXEC
  [[ -n "${K3S_VERSION:-}" ]] && export INSTALL_K3S_VERSION="$K3S_VERSION"
  retry curl -fsSL https://get.k3s.io -o /tmp/k3s-install.sh
  sh /tmp/k3s-install.sh
  rm -f /tmp/k3s-install.sh
fi

systemctl enable --now k3s

zz_log i "[vps-setup] Waiting for k3s node to become Ready..."
for i in $(seq 1 30); do
  if k3s kubectl get nodes 2>/dev/null | grep -q ' Ready'; then
    break
  fi
  sleep 5
done
k3s kubectl get nodes

if [[ ! -e /usr/local/bin/kubectl ]]; then
  ln -s "$(command -v k3s)" /usr/local/bin/kubectl
fi

mkdir -p /etc/rancher/k3s
KUBECONFIG_PATH=/etc/rancher/k3s/k3s.yaml
chmod 644 "$KUBECONFIG_PATH"
ensure_line "export KUBECONFIG=${KUBECONFIG_PATH}" /etc/profile.d/k3s-kubeconfig.sh
chmod 644 /etc/profile.d/k3s-kubeconfig.sh
export KUBECONFIG="$KUBECONFIG_PATH"

if command_exists helm; then
  zz_log i "[vps-setup] Helm already installed ($(helm version --short))."
else
  zz_log i "[vps-setup] Installing Helm..."
  retry curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o /tmp/get-helm-3.sh
  chmod +x /tmp/get-helm-3.sh
  /tmp/get-helm-3.sh
  rm -f /tmp/get-helm-3.sh
fi

ok "k3s, kubectl and helm are installed. KUBECONFIG=${KUBECONFIG_PATH}"

TRAEFIK_ACME_EMAIL="${TRAEFIK_ACME_EMAIL:-admin@example.com}"
TRAEFIK_ACME_STAGING="${TRAEFIK_ACME_STAGING:-true}"
TRAEFIK_DASHBOARD_PORT="${TRAEFIK_DASHBOARD_PORT:-$(net_port traefik_dashboard)}"

if [[ "$TRAEFIK_ACME_EMAIL" == "admin@example.com" ]]; then
  zz_log w "[vps-setup] TRAEFIK_ACME_EMAIL not set - using a placeholder. Let's Encrypt will" \
       "still issue certs with it, but you won't get expiry/problem notices." \
       "Set TRAEFIK_ACME_EMAIL to a real address you control."
fi
if [[ "$TRAEFIK_ACME_STAGING" == "true" ]]; then
  zz_log w "[vps-setup] TRAEFIK_ACME_STAGING=true (default): Let's Encrypt's staging" \
       "environment issues untrusted certs (browsers will warn) but has no" \
       "rate limit - safe to test against repeatedly. Set" \
       "TRAEFIK_ACME_STAGING=false for real, trusted certs once ready" \
       "(production Let's Encrypt has strict per-domain rate limits, so" \
       "avoid iterating against it)."
fi

STAGING_CASERVER_LINE=""
if [[ "$TRAEFIK_ACME_STAGING" == "true" ]]; then
  STAGING_CASERVER_LINE='      - "--certificatesresolvers.letsencrypt.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory"'
fi

zz_log i "[vps-setup] Configuring Traefik (public ingress on 80/443, Let's Encrypt, dashboard on ${TRAEFIK_DASHBOARD_PORT})..."
cat <<EOF | kubectl apply -f -
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    ports:
      traefik:
        port: 9000
        expose:
          default: true
        exposedPort: ${TRAEFIK_DASHBOARD_PORT}
    api:
      dashboard: true
      insecure: true
    persistence:
      enabled: true
      size: 128Mi
    additionalArguments:
      - "--certificatesresolvers.letsencrypt.acme.email=${TRAEFIK_ACME_EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/data/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
${STAGING_CASERVER_LINE}
EOF

zz_log i "[vps-setup] Waiting for k3s's helm-controller to apply the Traefik config (creates/updates the job)..."
for i in $(seq 1 30); do
  kubectl -n kube-system get deploy traefik >/dev/null 2>&1 && break
  sleep 5
done
kubectl -n kube-system rollout status deploy/traefik --timeout=5m || \
  zz_log w "[vps-setup] Traefik didn't report ready in time - check: kubectl -n kube-system get pods -l app.kubernetes.io/name=traefik"

ok "Traefik configured: HTTP/HTTPS public on 80/443, dashboard on ${TRAEFIK_DASHBOARD_PORT} (Tailscale-only)."
}

down() {
  require_root
  if [[ -x /usr/local/bin/k3s-uninstall.sh ]]; then
    zz_log i "[vps-setup] Uninstalling k3s (this also removes everything deployed on it: Rancher, any Marketplace-installed apps, etc.)..."
    /usr/local/bin/k3s-uninstall.sh
  else
    zz_log w "[vps-setup] k3s uninstall script not found (/usr/local/bin/k3s-uninstall.sh); k3s may not be installed."
  fi
  rm -f /usr/local/bin/kubectl /etc/profile.d/k3s-kubeconfig.sh
  ok "k3s removed."
}

dispatch_action "$@"
