#!/usr/bin/env bash
# Coder on the cluster, following https://coder.com/docs/install/server/rancher
# (namespace, Bitnami PostgreSQL, db-url Secret, upstream chart) but with the
# helm CLI instead of the Rancher UI. Env vars: see README.

set -euo pipefail
zz-use "perspikapps/vps/vps-common@${VPS_SETUP_REPO_REF:-main}" zz-persist
# shellcheck disable=SC1091
. vps-common

CODER_NAMESPACE=coder
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

up() {
command_exists kubectl || { zz-log e "[vps-setup] kubectl not found; run vps-k3s/run.sh first."; exit 1; }
command_exists helm || { zz-log e "[vps-setup] helm not found; run vps-k3s/run.sh first."; exit 1; }

zz-log i "[vps-setup] Adding the Helm repositories (Bitnami for PostgreSQL, Coder for the chart)..."
helm repo add bitnami https://charts.bitnami.com/bitnami --force-update >/dev/null
helm repo add vps-coder https://helm.coder.com/v2 --force-update >/dev/null
helm repo update bitnami vps-coder >/dev/null || { zz-log e "[vps-setup] Could not fetch the Bitnami/Coder chart indexes."; exit 1; }

kubectl create namespace "$CODER_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# alphanumeric only, so it can sit in the connection URL unescaped
DB_PASSWORD="$(vps_secret CODER_DB_PASSWORD)"
if [[ -z "$DB_PASSWORD" ]]; then
  DB_PASSWORD="$(random_password 24)"
  vps_secret_set CODER_DB_PASSWORD "$DB_PASSWORD"
fi

zz-log i "[vps-setup] Installing PostgreSQL (coder-db)..."
# bitnamilegacy/postgresql is the image the Coder doc uses; recent Bitnami
# charts refuse a non-Bitnami image unless allowInsecureImages is set.
DB_VALUES="$(mktemp)"
jq -n --arg pw "$DB_PASSWORD" --arg size "${CODER_DB_STORAGE:-10Gi}" \
  '{image: {repository: "bitnamilegacy/postgresql"}, global: {security: {allowInsecureImages: true}},
    auth: {username: "coder", password: $pw, database: "coder"}, persistence: {size: $size}}' >"$DB_VALUES"
rc=0
run_with_progress "$CODER_NAMESPACE" "Coder PostgreSQL" \
  helm upgrade --install coder-db bitnami/postgresql -n "$CODER_NAMESPACE" --values "$DB_VALUES" --wait --timeout 10m || rc=$?
rm -f "$DB_VALUES"
if [[ "$rc" -ne 0 ]]; then dump_diagnostics "$CODER_NAMESPACE"; exit "$rc"; fi

kubectl -n "$CODER_NAMESPACE" create secret generic coder-db-url \
  --from-literal=url="postgres://coder:${DB_PASSWORD}@coder-db-postgresql.${CODER_NAMESPACE}.svc.cluster.local:5432/coder?sslmode=disable" \
  --dry-run=client -o yaml | kubectl apply -f -

# Exposed through k3s's Traefik (ingress class traefik, ports 80/443). The cookie
# Coder sets is scoped to the wildcard domain, so the dashboard host must sit
# under it: both come from one domain (vps-system's WILDCARD_DOMAIN, else nip.io).
WILDCARD="$(wildcard_domain)"
ACCESS_URL="${CODER_ACCESS_URL:-${WILDCARD:+http://coder.${WILDCARD}}}"
[[ -n "$ACCESS_URL" ]] || { zz-log e "[vps-setup] No access URL: set CODER_ACCESS_URL or WILDCARD_DOMAIN."; exit 1; }
HOST="${ACCESS_URL#*://}"; HOST="${HOST%%[:/]*}"
VALUES_FILE="$(mktemp)"
jq -n --arg url "$ACCESS_URL" --arg host "$HOST" --arg wildcard "${WILDCARD:+*.${WILDCARD}}" \
  '{coder: {env: ([
      {name: "CODER_PG_CONNECTION_URL", valueFrom: {secretKeyRef: {name: "coder-db-url", key: "url"}}},
      {name: "CODER_ACCESS_URL", value: $url}]
      + (if $wildcard == "" then [] else [{name: "CODER_WILDCARD_ACCESS_URL", value: $wildcard}] end)),
    service: {type: "ClusterIP"},
    ingress: ({enable: true, className: "traefik", host: $host}
      + (if $wildcard == "" then {} else {wildcardHost: $wildcard} end))}}' >"$VALUES_FILE"
CHART_VERSION_ARG=()
[[ -z "${CODER_CHART_VERSION:-}" ]] || CHART_VERSION_ARG=(--version "$CODER_CHART_VERSION")

zz-log i "[vps-setup] Installing/upgrading Coder (access URL ${ACCESS_URL})..."
rc=0
run_with_progress "$CODER_NAMESPACE" "Coder install" \
  helm upgrade --install coder vps-coder/coder -n "$CODER_NAMESPACE" --values "$VALUES_FILE" \
  "${CHART_VERSION_ARG[@]}" --timeout 10m || rc=$?
rm -f "$VALUES_FILE"
if [[ "$rc" -ne 0 ]]; then dump_diagnostics "$CODER_NAMESPACE"; exit "$rc"; fi

if ! run_with_progress "$CODER_NAMESPACE" "Coder rollout" kubectl -n "$CODER_NAMESPACE" rollout status deploy/coder --timeout=10m; then
  dump_diagnostics "$CODER_NAMESPACE"
  zz-log e "[vps-setup] Coder did not become ready in time; re-run: sudo vps-setup --only-vps-coder"
  exit 1
fi

ok "Coder installed: ${ACCESS_URL} (via Traefik; the first visit creates the admin account)."
}

down() {
  command_exists kubectl || { zz-log w "[vps-setup] kubectl not found; nothing to remove."; return; }
  zz-log w "[vps-setup] Removing the coder namespace also deletes the PostgreSQL volume: all Coder data is lost."
  helm_teardown "$CODER_NAMESPACE" coder
  vps_secret_unset CODER_DB_PASSWORD
  ok "Coder removed."
}

summary() {
  # Opt-in step: say nothing on a host that never installed it.
  command_exists kubectl && kubectl get namespace "$CODER_NAMESPACE" >/dev/null 2>&1 || return 0
  local host
  host="$(kubectl -n "$CODER_NAMESPACE" get ingress coder -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || true)"
  cat <<EOF2
 Coder:               http://${host:-<coder host>} (through Traefik on 80/443 - public;
                       the first visit creates the admin account)
EOF2
}

dispatch_action "$@"
