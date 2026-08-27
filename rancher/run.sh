#!/usr/bin/env bash
# Rancher on k3s. Env vars: see README.

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

RANCHER_HTTP_PORT="${RANCHER_HTTP_PORT:-$(net_port rancher_http)}"
RANCHER_HTTPS_PORT="${RANCHER_HTTPS_PORT:-$(net_port rancher_https)}"
RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-$(hostname -I | awk '{print $1}')}"

PW_FILE=/root/.rancher-bootstrap-password
if [[ -z "${RANCHER_BOOTSTRAP_PASSWORD:-}" ]]; then
  if [[ -f "$PW_FILE" ]]; then
    RANCHER_BOOTSTRAP_PASSWORD="$(cat "$PW_FILE")"
  else
    RANCHER_BOOTSTRAP_PASSWORD="$(random_password 24)"
  fi
fi
umask 077
echo "$RANCHER_BOOTSTRAP_PASSWORD" > "$PW_FILE"

helm repo add rancher-latest https://releases.rancher.com/server-charts/latest >/dev/null 2>&1 || true
helm repo update >/dev/null

ensure_cert_manager

kubectl create namespace cattle-system --dry-run=client -o yaml | kubectl apply -f -

CHART_VERSION_ARG=()
[[ -n "${RANCHER_CHART_VERSION:-}" ]] && CHART_VERSION_ARG=(--version "$RANCHER_CHART_VERSION")

log "Installing/upgrading Rancher (hostname=${RANCHER_HOSTNAME})..."
helm upgrade --install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --set hostname="${RANCHER_HOSTNAME}" \
  --set bootstrapPassword="${RANCHER_BOOTSTRAP_PASSWORD}" \
  --set ingress.enabled=false \
  --set service.type=LoadBalancer \
  --set replicas=1 \
  "${CHART_VERSION_ARG[@]}" \
  --wait --timeout 10m

log "Rebinding the rancher Service to ports ${RANCHER_HTTP_PORT}/${RANCHER_HTTPS_PORT}..."
patch_service_port cattle-system rancher http "$RANCHER_HTTP_PORT" || true
patch_service_port cattle-system rancher https "$RANCHER_HTTPS_PORT" || true

log "Waiting for Rancher pods to be ready..."
kubectl -n cattle-system rollout status deploy/rancher --timeout=10m

ok "Rancher installed."
ok "UI: https://${RANCHER_HOSTNAME}:${RANCHER_HTTPS_PORT} (also plain-port ${RANCHER_HTTP_PORT})"
ok "Bootstrap password saved to ${PW_FILE}: ${RANCHER_BOOTSTRAP_PASSWORD}"
}

down() {
  require_root
  export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
  command_exists kubectl || { warn "kubectl not found; nothing to remove."; return; }
  helm_teardown cattle-system rancher
  rm -f /root/.rancher-bootstrap-password
  ok "Rancher removed."
}

dispatch_action "$@"
