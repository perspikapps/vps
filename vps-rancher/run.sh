#!/usr/bin/env bash
# Rancher on k3s. Env vars: see README.

set -euo pipefail
zz-use "perspikapps/vps/vps-common@${VPS_SETUP_REPO_REF:-main}" zz-persist
# shellcheck disable=SC1091
. vps-common
# vps-common comes from zz-use's download cache (24h for a branch), while the
# steps come from the fresh checkout: an older cached copy lacks newer helpers.
declare -F run_with_progress >/dev/null || {
  zz-log e "[vps-setup] The cached vps-common is older than this step. Refresh it and re-run:" \
       "sudo zz-use --force perspikapps/vps/vps-common"
  exit 1
}

up() {
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
command_exists kubectl || { zz-log e "[vps-setup] kubectl not found; run vps-k3s/run.sh first."; exit 1; }
command_exists helm || { zz-log e "[vps-setup] helm not found; run vps-k3s/run.sh first."; exit 1; }

RANCHER_HTTP_PORT="$(net_port rancher_http)"
RANCHER_HTTPS_PORT="$(net_port rancher_https)"
RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-$(hostname -I | awk '{print $1}')}"

RANCHER_BOOTSTRAP_PASSWORD="$(vps_secret RANCHER_BOOTSTRAP_PASSWORD /root/.rancher-bootstrap-password)"
[[ -n "$RANCHER_BOOTSTRAP_PASSWORD" ]] || RANCHER_BOOTSTRAP_PASSWORD="$(random_password 24)"
vps_secret_set RANCHER_BOOTSTRAP_PASSWORD "$RANCHER_BOOTSTRAP_PASSWORD" /root/.rancher-bootstrap-password

helm repo add rancher-latest https://releases.rancher.com/server-charts/latest >/dev/null 2>&1 || true
helm repo update >/dev/null

ensure_cert_manager

kubectl create namespace cattle-system --dry-run=client -o yaml | kubectl apply -f -

CHART_VERSION_ARG=()
[[ -n "${RANCHER_CHART_VERSION:-}" ]] && CHART_VERSION_ARG=(--version "$RANCHER_CHART_VERSION")

zz-log i "[vps-setup] Installing/upgrading Rancher (hostname=${RANCHER_HOSTNAME}); this usually takes 3-8 minutes (images are pulled), status every ${PROGRESS_INTERVAL:-15}s..."
# hostname and bootstrapPassword go through a values file with JSON-quoted
# strings, not --set: helm parses --set bootstrapPassword=12345678 as an
# integer and the chart's b64enc then fails ("wrong type for value; expected
# string; got int64"); --set also splits on commas and shows in `ps`.
VALUES_FILE="$(mktemp)"
jq -n --arg hostname "$RANCHER_HOSTNAME" --arg bootstrapPassword "$RANCHER_BOOTSTRAP_PASSWORD" \
  '{hostname: $hostname, bootstrapPassword: $bootstrapPassword}' > "$VALUES_FILE"
# No --wait here: helm would wait for the LoadBalancer Service to get an
# address, but k3s's ServiceLB cannot place it while Traefik holds host ports
# 80/443, and it is the rebind below that frees them - waiting first deadlocks
# ("UPGRADE FAILED: context deadline exceeded"). The rollout wait below does
# the waiting, once the Service is on its own ports.
# A re-run finds the Service already rebound (7080/7083 below): helm would merge
# the chart's 80/http and 443/https into it and the API rejects the duplicate
# port names ("spec.ports[2].name: Duplicate value: http"). Remove it so helm
# recreates it from the chart; it is rebound again right after. Pods keep running.
if kubectl -n cattle-system get service rancher >/dev/null 2>&1; then
  zz-log i "[vps-setup] Removing the already-rebound rancher Service so helm can recreate it (rebound again below)..."
  kubectl -n cattle-system delete service rancher --wait=true
fi

rc=0
run_with_progress cattle-system "Rancher install" \
  helm upgrade --install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --values "$VALUES_FILE" \
  --set ingress.enabled=false \
  --set service.type=LoadBalancer \
  --set replicas=1 \
  "${CHART_VERSION_ARG[@]}" \
  --timeout 10m || rc=$?
rm -f "$VALUES_FILE"
if [[ "$rc" -ne 0 ]]; then
  dump_diagnostics cattle-system
  exit "$rc"
fi

zz-log i "[vps-setup] Rebinding the rancher Service to ports ${RANCHER_HTTP_PORT}/${RANCHER_HTTPS_PORT}..."
patch_service_port cattle-system rancher http "$RANCHER_HTTP_PORT" || true
patch_service_port cattle-system rancher https "$RANCHER_HTTPS_PORT" || true

zz-log i "[vps-setup] Waiting for Rancher pods to be ready..."
if ! run_with_progress cattle-system "Rancher rollout" kubectl -n cattle-system rollout status deploy/rancher --timeout=10m; then
  dump_diagnostics cattle-system
  zz-log e "[vps-setup] Rancher did not become ready in time (see the diagnostics above); re-run: sudo vps-setup --only-vps-rancher"
  exit 1
fi

ok "Rancher installed."
ok "UI: https://${RANCHER_HOSTNAME}:${RANCHER_HTTPS_PORT} (also plain-port ${RANCHER_HTTP_PORT})"
ok "Bootstrap password saved to ${VPS_SECRETS_FILE}: ${RANCHER_BOOTSTRAP_PASSWORD}"
}

down() {
  export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
  command_exists kubectl || { zz-log w "[vps-setup] kubectl not found; nothing to remove."; return; }
  helm_teardown cattle-system rancher
  vps_secret_unset RANCHER_BOOTSTRAP_PASSWORD /root/.rancher-bootstrap-password
  ok "Rancher removed."
}

summary() {
  cat <<EOF
 Rancher:             https://${RANCHER_HOSTNAME:-$(summary_host)}:$(net_port rancher_https)
                       (also on plain port $(net_port rancher_http))
                       user:     admin
                       password: $(vps_secret RANCHER_BOOTSTRAP_PASSWORD /root/.rancher-bootstrap-password | grep . || echo 'not set - run vps-rancher/run.sh')
                       (saved to ${VPS_SECRETS_FILE}; you'll
                       be prompted to change it on first login)
EOF
}

dispatch_action "$@"
