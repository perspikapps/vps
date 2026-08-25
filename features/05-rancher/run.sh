#!/usr/bin/env bash
# Install the latest SUSE Rancher release onto the k3s cluster from
# features/04-k3s, exposed on RANCHER_HTTP_PORT/RANCHER_HTTPS_PORT (default
# 7080/7083) via k3s's built-in ServiceLB (Klipper), which binds those
# host ports directly -- no external load balancer needed for a single node.
#
# Env vars:
#   RANCHER_HOSTNAME            - FQDN/IP used in Rancher's self-signed cert
#                                 (default: the node's primary IP)
#   RANCHER_BOOTSTRAP_PASSWORD  - initial admin password (default: random,
#                                 printed at the end and saved to
#                                 /root/.rancher-bootstrap-password)
#   RANCHER_HTTP_PORT           - default from ../network.yaml (rancher_http)
#   RANCHER_HTTPS_PORT          - default from ../network.yaml (rancher_https)
#   RANCHER_CHART_VERSION       - pin a chart version (optional, default: latest)
#   CERT_MANAGER_VERSION        - pin cert-manager's chart version (optional)
#
# Installs cert-manager first: Rancher's default self-signed TLS source
# requires it to issue certs even when ingress is disabled.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../lib/common.sh"

up() {
require_root
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
command_exists kubectl || die "kubectl not found; run features/04-k3s/run.sh first."
command_exists helm || die "helm not found; run features/04-k3s/run.sh first."

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

log "Adding rancher-latest Helm repo..."
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest >/dev/null 2>&1 || true
helm repo update >/dev/null

# Rancher's default self-signed TLS source ("rancher") issues certs through
# cert-manager regardless of whether an ingress is deployed, so without this
# the rancher pod never becomes Ready and `helm ... --wait` below times out,
# aborting the whole dispatch.sh run.
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

# Uninstalls the Rancher Helm release and its namespace. Leaves cert-manager
# in place (features/08-epinio/run.sh may also depend on it - see ensure_cert_manager
# in lib/common.sh) and k3s itself untouched.
down() {
  require_root
  export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
  command_exists kubectl || { warn "kubectl not found; nothing to remove."; return; }
  helm_teardown cattle-system rancher
  rm -f /root/.rancher-bootstrap-password
  ok "Rancher removed."
}

dispatch_action "$@"
