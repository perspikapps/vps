#!/usr/bin/env bash
# Epinio on k3s. Env vars: see README.

set -euo pipefail
command -v zz_use >/dev/null 2>&1 || { echo "zz_use not found on PATH - run this repo's setup.sh first: curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/setup.sh | sh" >&2; exit 1; }
zz_use "perspikapps/vps/common@${VPS_SETUP_REPO_REF:-main}"
# shellcheck disable=SC1091
. common

up() {
require_root
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
command_exists kubectl || die "kubectl not found; run k3s/run.sh first."
command_exists helm || die "helm not found; run k3s/run.sh first."

NODE_PUBLIC_IP="$(hostname -I | awk '{print $1}')"
if [[ -z "${EPINIO_DOMAIN:-}" ]]; then
  EPINIO_DOMAIN="${NODE_PUBLIC_IP}.sslip.io"
  warn "EPINIO_DOMAIN not set - using ${EPINIO_DOMAIN} (sslip.io magic DNS)." \
       "Fine to try Epinio with, but set EPINIO_DOMAIN to a real wildcard" \
       "domain you control (pointed at this VPS's public IP) before" \
       "relying on this for anything real."
fi
EPINIO_INGRESS_CLASS="${EPINIO_INGRESS_CLASS:-traefik}"
EPINIO_TLS_ISSUER="${EPINIO_TLS_ISSUER:-epinio-ca}"
EPINIO_INSTALL_TIMEOUT="${EPINIO_INSTALL_TIMEOUT:-15m}"

PW_FILE=/root/.epinio-admin-password
if [[ -z "${EPINIO_ADMIN_PASSWORD:-}" ]]; then
  if [[ -f "$PW_FILE" ]]; then
    EPINIO_ADMIN_PASSWORD="$(cat "$PW_FILE")"
  else
    EPINIO_ADMIN_PASSWORD="$(random_password 24)"
  fi
fi
umask 077
echo "$EPINIO_ADMIN_PASSWORD" > "$PW_FILE"
umask 022

log "Adding epinio Helm repo..."
helm repo add epinio https://epinio.github.io/helm-charts/ >/dev/null 2>&1 || true
helm repo update >/dev/null

ensure_cert_manager

kubectl create namespace epinio --dry-run=client -o yaml | kubectl apply -f -

CHART_VERSION_ARG=()
[[ -n "${EPINIO_CHART_VERSION:-}" ]] && CHART_VERSION_ARG=(--version "$EPINIO_CHART_VERSION")

log "Installing/upgrading Epinio (domain=${EPINIO_DOMAIN}, ingressClass=${EPINIO_INGRESS_CLASS}, tlsIssuer=${EPINIO_TLS_ISSUER}, timeout ${EPINIO_INSTALL_TIMEOUT})..."
if ! helm upgrade --install epinio epinio/epinio \
  --namespace epinio \
  --set global.domain="$EPINIO_DOMAIN" \
  --set global.tlsIssuer="$EPINIO_TLS_ISSUER" \
  --set api.adminPassword="$EPINIO_ADMIN_PASSWORD" \
  --set ingress.ingressClassName="$EPINIO_INGRESS_CLASS" \
  --set server.ingressClassName="$EPINIO_INGRESS_CLASS" \
  --set containerregistry.ingressClassName="$EPINIO_INGRESS_CLASS" \
  "${CHART_VERSION_ARG[@]}" \
  --wait --timeout "$EPINIO_INSTALL_TIMEOUT"; then
  warn "helm install/upgrade timed out or failed - pod status for diagnosis:"
  kubectl -n epinio get pods -o wide || true
  warn "Recent events:"
  kubectl -n epinio get events --sort-by=.lastTimestamp 2>/dev/null | tail -30 || true
  die "Epinio install did not finish within ${EPINIO_INSTALL_TIMEOUT}." \
      "Often just a slow first image pull (this chart also deploys" \
      "SeaweedFS for S3 storage, its own container registry, and Dex) -" \
      "check the pod status above for Pending/ImagePullBackOff, then" \
      "re-run: sudo sh dispatch.sh --only-epinio (helm resumes the same" \
      "release, it won't re-pull images already cached). To wait longer" \
      "instead, set EPINIO_INSTALL_TIMEOUT=25m (or similar) and re-run."
fi

log "Installing the epinio CLI..."
case "$(dpkg --print-architecture)" in
  amd64) EPINIO_CLI_ARCH=x86_64 ;;
  arm64) EPINIO_CLI_ARCH=arm64 ;;
  *) die "Unsupported architecture for the epinio CLI: $(dpkg --print-architecture)" ;;
esac
retry curl -fsSL "https://github.com/epinio/epinio/releases/latest/download/epinio-linux-${EPINIO_CLI_ARCH}" -o /usr/local/bin/epinio
chmod +x /usr/local/bin/epinio

ok "Epinio installed."
ok "Dashboard/API: https://epinio.${EPINIO_DOMAIN} (user: admin)"
ok "Admin password saved to ${PW_FILE}: ${EPINIO_ADMIN_PASSWORD}"
ok "Log in with: epinio login -u admin -p '${EPINIO_ADMIN_PASSWORD}' https://epinio.${EPINIO_DOMAIN}"
if [[ "$EPINIO_DOMAIN" == *.sslip.io ]]; then
  warn "Using sslip.io magic DNS - fine to try Epinio with, but point" \
       "EPINIO_DOMAIN at a real domain you own before deploying anything" \
       "you care about."
fi
}

down() {
  require_root
  export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
  command_exists kubectl || { warn "kubectl not found; nothing to remove."; return; }
  helm_teardown epinio epinio
  rm -f /usr/local/bin/epinio /root/.epinio-admin-password
  ok "Epinio removed."
}

dispatch_action "$@"
