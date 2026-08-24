#!/usr/bin/env bash
# Install ArgoCD onto the k3s cluster from scripts/05, for GitOps-managed
# deployments (a natural pairing with Rancher for cluster management - see
# https://oneuptime.com/blog/post/2026-03-20-rancher-argocd/view).
#
# Exposed on ARGOCD_HTTP_PORT/ARGOCD_HTTPS_PORT (default 7090/7093) via
# k3s's built-in ServiceLB, Tailscale-only like Cockpit/Rancher/the Traefik
# dashboard (see scripts/02-security-harden.sh's Security model).
#
# Env vars:
#   ARGOCD_HTTP_PORT      - default from ../network.yaml (argocd_http)
#   ARGOCD_HTTPS_PORT     - default from ../network.yaml (argocd_https)
#   ARGOCD_CHART_VERSION  - pin a chart version (optional, default: latest)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

require_root
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
command_exists kubectl || die "kubectl not found; run scripts/05-k3s.sh first."
command_exists helm || die "helm not found; run scripts/05-k3s.sh first."

ARGOCD_HTTP_PORT="${ARGOCD_HTTP_PORT:-$(net_port argocd_http)}"
ARGOCD_HTTPS_PORT="${ARGOCD_HTTPS_PORT:-$(net_port argocd_https)}"

log "Adding argo Helm repo..."
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

CHART_VERSION_ARG=()
[[ -n "${ARGOCD_CHART_VERSION:-}" ]] && CHART_VERSION_ARG=(--version "$ARGOCD_CHART_VERSION")

log "Installing/upgrading ArgoCD..."
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --set server.service.type=LoadBalancer \
  --set configs.params."server\.insecure"=true \
  "${CHART_VERSION_ARG[@]}" \
  --wait --timeout 10m

log "Rebinding the argocd-server Service to ports ${ARGOCD_HTTP_PORT}/${ARGOCD_HTTPS_PORT}..."
patch_service_port argocd argocd-server http "$ARGOCD_HTTP_PORT" || true
patch_service_port argocd argocd-server https "$ARGOCD_HTTPS_PORT" || true

log "Waiting for ArgoCD server to be ready..."
kubectl -n argocd rollout status deploy/argocd-server --timeout=10m

PW_FILE=/root/.argocd-admin-password
log "Reading ArgoCD's generated initial admin password..."
for i in $(seq 1 12); do
  if kubectl -n argocd get secret argocd-initial-admin-secret >/dev/null 2>&1; then
    break
  fi
  sleep 5
done
if kubectl -n argocd get secret argocd-initial-admin-secret >/dev/null 2>&1; then
  umask 077
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d > "$PW_FILE"
  echo >> "$PW_FILE"
  umask 022
else
  warn "argocd-initial-admin-secret not found (it's deleted after the admin" \
       "password is changed) - if this is a re-run, your existing password" \
       "still works; check ${PW_FILE} from the original install."
fi

ok "ArgoCD installed."
ok "UI: https://<tailscale-ip>:${ARGOCD_HTTPS_PORT} (also plain-port ${ARGOCD_HTTP_PORT}, user: admin)"
[[ -f "$PW_FILE" ]] && ok "Admin password saved to ${PW_FILE}: $(cat "$PW_FILE")"
