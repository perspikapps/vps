#!/usr/bin/env bash
# Deploys Coder (https://coder.com), a self-hosted remote development
# platform, as a Helm release into the k3s cluster from scripts/05 - it
# then shows up in Rancher's own Apps view like any other in-cluster Helm
# release, unlike Laranode (scripts/08) which has no container image and
# runs natively on the host instead.
#
# Coder's chart ships no bundled database, so this also deploys a minimal
# single-replica Postgres (official postgres image + a PVC on k3s's
# default local-path StorageClass) to back it - fine for this repo's
# single-node scope, not meant to be HA.
#
# Exposed on CODER_HTTP_PORT (default 8090) via k3s's built-in ServiceLB,
# same pattern as scripts/06-rancher.sh. Plain HTTP: the transport is
# already encrypted by Tailscale itself since this is Tailscale-only by
# default (see scripts/02-security-harden.sh); set coder.tls.secretNames
# yourself via CODER_EXTRA_HELM_ARGS if you want the chart to terminate
# TLS instead.
#
# The initial admin user is created non-interactively via
# `coder server create-admin-user` (run as a one-off Job using the same
# image), since Coder has no bootstrap-password chart value the way
# Rancher does.
#
# Env vars:
#   CODER_HOSTNAME              - FQDN/IP used in CODER_ACCESS_URL
#                                 (default: the node's primary IP)
#   CODER_HTTP_PORT             - default 8090
#   CODER_ADMIN_USERNAME        - default "admin"
#   CODER_ADMIN_EMAIL           - default "admin@<CODER_HOSTNAME>"
#   CODER_ADMIN_PASSWORD        - initial admin password (default: random,
#                                 saved to /root/.coder-admin-password)
#   CODER_POSTGRES_PASSWORD     - Postgres password (default: random, saved
#                                 to /root/.coder-postgres-password)
#   CODER_CHART_VERSION         - pin a chart version (optional, default: latest)
#   CODER_EXTRA_HELM_ARGS       - extra args appended to `helm upgrade --install` (optional)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

require_root
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
command_exists kubectl || die "kubectl not found; run scripts/05-k3s.sh first."
command_exists helm || die "helm not found; run scripts/05-k3s.sh first."

CODER_HTTP_PORT="${CODER_HTTP_PORT:-8090}"
CODER_HOSTNAME="${CODER_HOSTNAME:-$(hostname -I | awk '{print $1}')}"
CODER_ADMIN_USERNAME="${CODER_ADMIN_USERNAME:-admin}"
CODER_ADMIN_EMAIL="${CODER_ADMIN_EMAIL:-admin@${CODER_HOSTNAME}}"
NAMESPACE=coder

PG_PW_FILE=/root/.coder-postgres-password
if [[ -z "${CODER_POSTGRES_PASSWORD:-}" ]]; then
  if [[ -f "$PG_PW_FILE" ]]; then
    CODER_POSTGRES_PASSWORD="$(cat "$PG_PW_FILE")"
  else
    CODER_POSTGRES_PASSWORD="$(random_password 24)"
  fi
fi
umask 077
echo "$CODER_POSTGRES_PASSWORD" > "$PG_PW_FILE"

ADMIN_PW_FILE=/root/.coder-admin-password
if [[ -z "${CODER_ADMIN_PASSWORD:-}" ]]; then
  if [[ -f "$ADMIN_PW_FILE" ]]; then
    CODER_ADMIN_PASSWORD="$(cat "$ADMIN_PW_FILE")"
  else
    CODER_ADMIN_PASSWORD="$(random_password 24)"
  fi
fi
echo "$CODER_ADMIN_PASSWORD" > "$ADMIN_PW_FILE"
umask 022

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

log "Deploying a minimal Postgres for Coder..."
kubectl -n "$NAMESPACE" create secret generic coder-postgres \
  --from-literal=POSTGRES_USER=coder \
  --from-literal=POSTGRES_PASSWORD="${CODER_POSTGRES_PASSWORD}" \
  --from-literal=POSTGRES_DB=coder \
  --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: coder-postgres-data
  namespace: ${NAMESPACE}
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 10Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coder-postgres
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels: {app: coder-postgres}
  template:
    metadata:
      labels: {app: coder-postgres}
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          envFrom:
            - secretRef: {name: coder-postgres}
          ports:
            - containerPort: 5432
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
              subPath: postgres
      volumes:
        - name: data
          persistentVolumeClaim: {claimName: coder-postgres-data}
---
apiVersion: v1
kind: Service
metadata:
  name: coder-postgres
  namespace: ${NAMESPACE}
spec:
  selector: {app: coder-postgres}
  ports:
    - port: 5432
      targetPort: 5432
EOF

log "Waiting for Postgres to be ready..."
kubectl -n "$NAMESPACE" rollout status deploy/coder-postgres --timeout=5m

log "Adding the coder-v2 Helm repo..."
helm repo add coder-v2 https://helm.coder.com/v2 >/dev/null 2>&1 || true
helm repo update >/dev/null

PG_CONNECTION_URL="postgres://coder:${CODER_POSTGRES_PASSWORD}@coder-postgres.${NAMESPACE}.svc.cluster.local:5432/coder?sslmode=disable"
CODER_ACCESS_URL="http://${CODER_HOSTNAME}:${CODER_HTTP_PORT}"

VALUES_FILE="$(mktemp --suffix=.yaml)"
trap 'rm -f "$VALUES_FILE"' EXIT
cat > "$VALUES_FILE" <<EOF
coder:
  env:
    - name: CODER_PG_CONNECTION_URL
      value: "${PG_CONNECTION_URL}"
    - name: CODER_ACCESS_URL
      value: "${CODER_ACCESS_URL}"
  service:
    type: LoadBalancer
EOF

CHART_VERSION_ARG=()
[[ -n "${CODER_CHART_VERSION:-}" ]] && CHART_VERSION_ARG=(--version "$CODER_CHART_VERSION")

log "Installing/upgrading Coder (access URL: ${CODER_ACCESS_URL})..."
# shellcheck disable=SC2086
helm upgrade --install coder coder-v2/coder \
  --namespace "$NAMESPACE" \
  -f "$VALUES_FILE" \
  "${CHART_VERSION_ARG[@]}" \
  ${CODER_EXTRA_HELM_ARGS:-} \
  --wait --timeout 10m

log "Rebinding the coder Service to port ${CODER_HTTP_PORT}..."
patch_service_port "$NAMESPACE" coder http "$CODER_HTTP_PORT" || true

log "Waiting for Coder to be ready..."
kubectl -n "$NAMESPACE" rollout status deploy/coder --timeout=10m

ADMIN_MARKER=/root/.coder-admin-created
if [[ -f "$ADMIN_MARKER" ]]; then
  log "Initial admin user already created previously (${ADMIN_MARKER} exists); skipping."
else
  log "Creating the initial admin user (${CODER_ADMIN_USERNAME})..."
  CODER_IMAGE="$(kubectl -n "$NAMESPACE" get deploy coder -o jsonpath='{.spec.template.spec.containers[0].image}')"
  kubectl -n "$NAMESPACE" delete job coder-create-admin --ignore-not-found >/dev/null
  cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: coder-create-admin
  namespace: ${NAMESPACE}
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: create-admin-user
          image: ${CODER_IMAGE}
          args: ["server", "create-admin-user"]
          env:
            - name: CODER_PG_CONNECTION_URL
              value: "${PG_CONNECTION_URL}"
            - name: CODER_USERNAME
              value: "${CODER_ADMIN_USERNAME}"
            - name: CODER_EMAIL
              value: "${CODER_ADMIN_EMAIL}"
            - name: CODER_PASSWORD
              value: "${CODER_ADMIN_PASSWORD}"
EOF
  if kubectl -n "$NAMESPACE" wait --for=condition=complete job/coder-create-admin --timeout=2m; then
    touch "$ADMIN_MARKER"
    ok "Admin user created: ${CODER_ADMIN_USERNAME} / ${CODER_ADMIN_EMAIL}"
  else
    warn "Admin user creation did not complete cleanly - check:" \
         "kubectl -n ${NAMESPACE} logs job/coder-create-admin"
  fi
fi

ok "Coder installed."
ok "UI: ${CODER_ACCESS_URL}"
ok "Admin login: ${CODER_ADMIN_USERNAME} / ${CODER_ADMIN_PASSWORD} (saved to ${ADMIN_PW_FILE})"
