#!/usr/bin/env bash
# Rancher on k3s. Env vars: see README.

set -euo pipefail
zz-use "perspikapps/vps/vps-common@${ZZ_SETUP_REF:-main}" zz-persist
# shellcheck disable=SC1091
. vps-common
# vps-common comes from zz-use's download cache (24h for a branch), while the
# steps come from the fresh checkout: an older cached copy lacks newer helpers.
declare -F reapply_private_guard >/dev/null || {
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
# Public dashboard host (Traefik, same domain source as Coder): rancher.<wildcard domain>.
# RANCHER_INGRESS=false keeps Rancher private-only (ufw-guarded ports).
RANCHER_INGRESS="${RANCHER_INGRESS:-true}"
RANCHER_INGRESS_HOST_OVERRIDE="${RANCHER_INGRESS_HOST:-}"
RANCHER_INGRESS_HOST=""
if [[ "$RANCHER_INGRESS" == "true" ]]; then
  RANCHER_INGRESS_HOST="${RANCHER_INGRESS_HOST_OVERRIDE:-rancher.$(wildcard_domain)}"
  [[ "$RANCHER_INGRESS_HOST" != "rancher." ]] || { zz-log e "[vps-setup] No Rancher host: set RANCHER_INGRESS_HOST or WILDCARD_DOMAIN."; exit 1; }
fi
# Rancher's server URL follows the public host; without one, the private address.
RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-${RANCHER_INGRESS_HOST:-$(private_address)}}"
RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-$(hostname -I | awk '{print $1}')}"

RANCHER_BOOTSTRAP_PASSWORD="$(vps_secret RANCHER_BOOTSTRAP_PASSWORD /root/.rancher-bootstrap-password)"
[[ -n "$RANCHER_BOOTSTRAP_PASSWORD" ]] || RANCHER_BOOTSTRAP_PASSWORD="$(random_password 24)"
vps_secret_set RANCHER_BOOTSTRAP_PASSWORD "$RANCHER_BOOTSTRAP_PASSWORD" /root/.rancher-bootstrap-password

# Chart repository: the community "latest" channel by default; RANCHER_CHART_REPO_URL
# selects another, e.g. SUSE Rancher Prime (https://charts.rancher.com/server-charts/prime).
# --force-update lets a changed URL replace the alias from a previous run.
RANCHER_CHART_REPO_URL="${RANCHER_CHART_REPO_URL:-https://releases.rancher.com/server-charts/latest}"
case "$RANCHER_CHART_REPO_URL" in
  http://* | https://*) ;;
  *) zz-log e "[vps-setup] RANCHER_CHART_REPO_URL must be an http(s) Helm repository URL (got '${RANCHER_CHART_REPO_URL}')."; exit 1 ;;
esac
zz-log i "[vps-setup] Using the Rancher chart repository ${RANCHER_CHART_REPO_URL}"
helm repo add vps-rancher "$RANCHER_CHART_REPO_URL" --force-update >/dev/null || {
  zz-log e "[vps-setup] Could not add the Helm repository ${RANCHER_CHART_REPO_URL}."
  exit 1
}
helm repo update vps-rancher >/dev/null || {
  zz-log e "[vps-setup] Could not fetch the chart index from ${RANCHER_CHART_REPO_URL} (check the URL and any access it needs)."
  exit 1
}

# Bitnami charts (e.g. the databases some Marketplace apps depend on) resolve from this alias.
helm repo add bitnami https://charts.bitnami.com/bitnami --force-update >/dev/null || {
  zz-log e "[vps-setup] Could not add the Helm repository https://charts.bitnami.com/bitnami."
  exit 1
}

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
  helm upgrade --install rancher vps-rancher/rancher \
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

# Public dashboard through k3s's Traefik. The backend is the Service's "http" port
# by name, so it survives the private-port rebind above; Traefik terminates TLS
# (Let's Encrypt) and sends X-Forwarded-Proto, which keeps Rancher from
# redirecting to https again.
if [[ -n "$RANCHER_INGRESS_HOST" ]]; then
zz-log i "[vps-setup] Exposing Rancher through Traefik at ${RANCHER_INGRESS_HOST}..."
kubectl apply -f - <<EOF2
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rancher-traefik
  namespace: cattle-system
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web,websecure
    traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt
spec:
  ingressClassName: traefik
  tls:
    - hosts: ["${RANCHER_INGRESS_HOST}"]
  rules:
    - host: ${RANCHER_INGRESS_HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: rancher
                port:
                  name: http
EOF2
else
  kubectl -n cattle-system delete ingress rancher-traefik --ignore-not-found
fi

reapply_private_guard

ok "Rancher installed."
[[ -z "$RANCHER_INGRESS_HOST" ]] || ok "UI: https://${RANCHER_INGRESS_HOST} (via Traefik, public)"
ok "UI (private): https://$(private_address):${RANCHER_HTTPS_PORT} (also plain-port ${RANCHER_HTTP_PORT})"
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
 Rancher:             $(kubectl -n cattle-system get ingress rancher-traefik -o jsonpath='https://{.spec.rules[0].host} (through Traefik - public)' 2>/dev/null || echo '(no public route)')
                       private: https://$(summary_host):$(net_port rancher_https)
                       (also on plain port $(net_port rancher_http))
                       user:     admin
                       password: $(vps_secret RANCHER_BOOTSTRAP_PASSWORD /root/.rancher-bootstrap-password | grep . || echo 'not set - run vps-rancher/run.sh')
                       (saved to ${VPS_SECRETS_FILE}; you'll
                       be prompted to change it on first login)
EOF
}

dispatch_action "$@"
