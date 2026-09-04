#!/usr/bin/env bash
# Registers this repo's Helm chart catalog as a Rancher Apps &
# Marketplace repository. Env vars: see README.

set -euo pipefail
command -v zz_use >/dev/null 2>&1 || { echo "zz_use not found on PATH - run this repo's setup.sh first: curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/setup.sh | sh" >&2; exit 1; }
zz_use "perspikapps/vps/vps-common@${VPS_SETUP_REPO_REF:-main}"
# shellcheck disable=SC1091
. vps-common

MARKETPLACE_REPO_NAME="${MARKETPLACE_REPO_NAME:-perspikapps-vps}"
MARKETPLACE_REPO_URL="${MARKETPLACE_REPO_URL:-https://perspikapps.github.io/vps/}"

up() {
require_root
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
command_exists kubectl || { zz_log e "[vps-setup] kubectl not found; run vps-k3s/run.sh first."; exit 1; }
kubectl get deploy -n cattle-system rancher >/dev/null 2>&1 || zz_log w "[vps-setup] Rancher doesn't look installed yet (no cattle-system/rancher" \
     "deployment) - registering the catalog anyway; it'll show up under" \
     "Apps & Marketplace once Rancher is up."

zz_log i "[vps-setup] Registering the ${MARKETPLACE_REPO_NAME} catalog (${MARKETPLACE_REPO_URL})..."
cat <<EOF | kubectl apply -f -
apiVersion: catalog.cattle.io/v1
kind: ClusterRepo
metadata:
  name: ${MARKETPLACE_REPO_NAME}
spec:
  url: ${MARKETPLACE_REPO_URL}
EOF

ok "Catalog '${MARKETPLACE_REPO_NAME}' registered."
ok "In Rancher: Apps & Marketplace -> Repositories, it should show up there" \
   "(may take a minute to sync). Install ArgoCD / Epinio from" \
   "Apps & Marketplace -> Charts once it does."
}

down() {
  require_root
  export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
  command_exists kubectl || { zz_log w "[vps-setup] kubectl not found; nothing to remove."; return; }
  kubectl delete clusterrepo "$MARKETPLACE_REPO_NAME" --ignore-not-found
  ok "Catalog '${MARKETPLACE_REPO_NAME}' removed (apps already installed from it are untouched)."
}

dispatch_action "$@"
