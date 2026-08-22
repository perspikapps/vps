#!/usr/bin/env bash
# Install the latest SUSE Rancher release onto the k3s cluster from
# scripts/05, exposed on RANCHER_HTTP_PORT/RANCHER_HTTPS_PORT (default
# 8080/8083) via k3s's built-in ServiceLB (Klipper), which binds those
# host ports directly -- no external load balancer needed for a single node.
#
# Env vars:
#   RANCHER_HOSTNAME            - FQDN/IP used in Rancher's self-signed cert
#                                 (default: the node's primary IP)
#   RANCHER_BOOTSTRAP_PASSWORD  - initial admin password (default: random,
#                                 printed at the end and saved to
#                                 /root/.rancher-bootstrap-password)
#   RANCHER_HTTP_PORT           - default 8080
#   RANCHER_HTTPS_PORT          - default 8083
#   RANCHER_CHART_VERSION       - pin a chart version (optional, default: latest)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

require_root
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
command_exists kubectl || die "kubectl not found; run scripts/05-k3s.sh first."
command_exists helm || die "helm not found; run scripts/05-k3s.sh first."

RANCHER_HTTP_PORT="${RANCHER_HTTP_PORT:-8080}"
RANCHER_HTTPS_PORT="${RANCHER_HTTPS_PORT:-8083}"
RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-$(hostname -I | awk '{print $1}')}"

PW_FILE=/root/.rancher-bootstrap-password
if [[ -z "${RANCHER_BOOTSTRAP_PASSWORD:-}" ]]; then
  if [[ -f "$PW_FILE" ]]; then
    RANCHER_BOOTSTRAP_PASSWORD="$(cat "$PW_FILE")"
  else
    RANCHER_BOOTSTRAP_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"
  fi
fi
umask 077
echo "$RANCHER_BOOTSTRAP_PASSWORD" > "$PW_FILE"

log "Adding rancher-latest Helm repo..."
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest >/dev/null 2>&1 || true
helm repo update >/dev/null

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
HTTP_IDX="$(kubectl -n cattle-system get service rancher -o json | jq '.spec.ports | map(.name) | index("http")')"
HTTPS_IDX="$(kubectl -n cattle-system get service rancher -o json | jq '.spec.ports | map(.name) | index("https")')"
PATCH_OPS="[]"
[[ "$HTTP_IDX" != "null" ]] && PATCH_OPS="$(jq -c ". + [{\"op\":\"replace\",\"path\":\"/spec/ports/${HTTP_IDX}/port\",\"value\":${RANCHER_HTTP_PORT}}]" <<<"$PATCH_OPS")"
[[ "$HTTPS_IDX" != "null" ]] && PATCH_OPS="$(jq -c ". + [{\"op\":\"replace\",\"path\":\"/spec/ports/${HTTPS_IDX}/port\",\"value\":${RANCHER_HTTPS_PORT}}]" <<<"$PATCH_OPS")"
if [[ "$PATCH_OPS" != "[]" ]]; then
  kubectl -n cattle-system patch service rancher --type=json -p "$PATCH_OPS"
else
  warn "Could not find named http/https ports on the rancher Service; leaving defaults (80/443)."
fi

log "Waiting for Rancher pods to be ready..."
kubectl -n cattle-system rollout status deploy/rancher --timeout=10m

ok "Rancher installed."
ok "UI: https://${RANCHER_HOSTNAME}:${RANCHER_HTTPS_PORT} (also plain-port ${RANCHER_HTTP_PORT})"
ok "Bootstrap password saved to ${PW_FILE}: ${RANCHER_BOOTSTRAP_PASSWORD}"
