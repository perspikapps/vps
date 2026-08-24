#!/usr/bin/env bash
# Install ArgoCD onto the k3s cluster from scripts/05, for GitOps-managed
# deployments (a natural pairing with Rancher for cluster management - see
# https://oneuptime.com/blog/post/2026-03-20-rancher-argocd/view).
#
# Exposed on ARGOCD_HTTP_PORT/ARGOCD_HTTPS_PORT (default 7090/7093) via
# k3s's built-in ServiceLB, Tailscale-only like Cockpit/Rancher/the Traefik
# dashboard (see scripts/02-security-harden.sh's Security model).
#
# dex (SSO) and the notifications controller are disabled: this repo only
# uses ArgoCD's built-in admin login, and skipping them means fewer pods
# to pull images for and wait on - meaningful on a small single-node VPS
# where that wait is what timed out before (see ARGOCD_INSTALL_TIMEOUT).
#
# Env vars:
#   ARGOCD_HTTP_PORT      - default from ../network.yaml (argocd_http)
#   ARGOCD_HTTPS_PORT     - default from ../network.yaml (argocd_https)
#   ARGOCD_CHART_VERSION  - pin a chart version (optional, default: latest)
#   ARGOCD_INSTALL_TIMEOUT - how long to wait for all pods to come up
#                            (default 15m; a small VPS pulling several
#                            images for the first time can be slow)

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

ARGOCD_INSTALL_TIMEOUT="${ARGOCD_INSTALL_TIMEOUT:-15m}"

log "Installing/upgrading ArgoCD (timeout ${ARGOCD_INSTALL_TIMEOUT})..."
if ! helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --set server.service.type=LoadBalancer \
  --set configs.params."server\.insecure"=true \
  --set dex.enabled=false \
  --set notifications.enabled=false \
  "${CHART_VERSION_ARG[@]}" \
  --wait --timeout "$ARGOCD_INSTALL_TIMEOUT"; then
  warn "helm install/upgrade timed out or failed - pod status for diagnosis:"
  kubectl -n argocd get pods -o wide || true
  warn "Recent events:"
  kubectl -n argocd get events --sort-by=.lastTimestamp 2>/dev/null | tail -30 || true
  die "ArgoCD install did not finish within ${ARGOCD_INSTALL_TIMEOUT}." \
      "Often just a slow first image pull on a small VPS - check the pod" \
      "status above for Pending/ImagePullBackOff, then re-run:" \
      "sudo bash setup.sh --only-argocd (helm resumes the same release," \
      "it won't re-pull images already cached). To wait longer instead," \
      "set ARGOCD_INSTALL_TIMEOUT=25m (or similar) and re-run."
fi

log "Rebinding the argocd-server Service to ports ${ARGOCD_HTTP_PORT}/${ARGOCD_HTTPS_PORT}..."
patch_service_port argocd argocd-server http "$ARGOCD_HTTP_PORT" || true
patch_service_port argocd argocd-server https "$ARGOCD_HTTPS_PORT" || true

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
