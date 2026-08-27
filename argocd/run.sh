#!/usr/bin/env bash
# ArgoCD on k3s. Env vars: see README.

set -euo pipefail
command -v zz_use >/dev/null 2>&1 || { echo "zz_use not found on PATH - run this repo's setup.sh first: curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/setup.sh | sh" >&2; exit 1; }
zz_use "perspikapps/vps/common@${VPS_SETUP_REPO_REF:-main}"
# shellcheck disable=SC1091
. common

up() {
require_root
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
command_exists kubectl || { zz_log e "[vps-setup] kubectl not found; run k3s/run.sh first."; exit 1; }
command_exists helm || { zz_log e "[vps-setup] helm not found; run k3s/run.sh first."; exit 1; }

ARGOCD_HTTP_PORT="${ARGOCD_HTTP_PORT:-$(net_port argocd_http)}"
ARGOCD_HTTPS_PORT="${ARGOCD_HTTPS_PORT:-$(net_port argocd_https)}"

zz_log i "[vps-setup] Adding argo Helm repo..."
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

CHART_VERSION_ARG=()
[[ -n "${ARGOCD_CHART_VERSION:-}" ]] && CHART_VERSION_ARG=(--version "$ARGOCD_CHART_VERSION")

ARGOCD_INSTALL_TIMEOUT="${ARGOCD_INSTALL_TIMEOUT:-15m}"

zz_log i "[vps-setup] Installing/upgrading ArgoCD (timeout ${ARGOCD_INSTALL_TIMEOUT})..."
if ! helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --set server.service.type=LoadBalancer \
  --set configs.params."server\.insecure"=true \
  --set dex.enabled=false \
  --set notifications.enabled=false \
  "${CHART_VERSION_ARG[@]}" \
  --wait --timeout "$ARGOCD_INSTALL_TIMEOUT"; then
  zz_log w "[vps-setup] helm install/upgrade timed out or failed - pod status for diagnosis:"
  kubectl -n argocd get pods -o wide || true
  zz_log w "[vps-setup] Recent events:"
  kubectl -n argocd get events --sort-by=.lastTimestamp 2>/dev/null | tail -30 || true
  zz_log e "[vps-setup] ArgoCD install did not finish within ${ARGOCD_INSTALL_TIMEOUT}." \
      "Often just a slow first image pull on a small VPS - check the pod" \
      "status above for Pending/ImagePullBackOff, then re-run:" \
      "sudo sh dispatch.sh --only-argocd (helm resumes the same release," \
      "it won't re-pull images already cached). To wait longer instead," \
      "set ARGOCD_INSTALL_TIMEOUT=25m (or similar) and re-run."
  exit 1
fi

zz_log i "[vps-setup] Rebinding the argocd-server Service to ports ${ARGOCD_HTTP_PORT}/${ARGOCD_HTTPS_PORT}..."
patch_service_port argocd argocd-server http "$ARGOCD_HTTP_PORT" || true
patch_service_port argocd argocd-server https "$ARGOCD_HTTPS_PORT" || true

PW_FILE=/root/.argocd-admin-password
zz_log i "[vps-setup] Reading ArgoCD's generated initial admin password..."
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
  zz_log w "[vps-setup] argocd-initial-admin-secret not found (it's deleted after the admin" \
       "password is changed) - if this is a re-run, your existing password" \
       "still works; check ${PW_FILE} from the original install."
fi

ok "ArgoCD installed."
ok "UI: https://<tailscale-ip>:${ARGOCD_HTTPS_PORT} (also plain-port ${ARGOCD_HTTP_PORT}, user: admin)"
[[ -f "$PW_FILE" ]] && ok "Admin password saved to ${PW_FILE}: $(cat "$PW_FILE")"
}

down() {
  require_root
  export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
  command_exists kubectl || { zz_log w "[vps-setup] kubectl not found; nothing to remove."; return; }
  helm_teardown argocd argocd
  rm -f /root/.argocd-admin-password
  ok "ArgoCD removed."
}

dispatch_action "$@"
