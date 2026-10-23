#!/bin/sh
# Registers this repo's Helm chart catalog as a Rancher Apps &
# Marketplace repository. Env vars: see README.

set -eu
zz-use zz-colors zz-log yaml-render
# shellcheck disable=SC1091
. zz-colors
# A step only defines up(), down() and summary(): zz-setup sources it. An older zz-setup runs
# it as `run.sh <action>` and nothing would happen.
[ "$#" -eq 0 ] || { zz-log e "[vps-setup] $0 needs a newer zz-setup (config.functions); refresh it: zz-use -f zz-setup zz-call zz-vars zz-workspaces" && exit 1; }

MARKETPLACE_REPO_NAME="${MARKETPLACE_REPO_NAME:-perspikapps-vps}"
MARKETPLACE_REPO_URL="${MARKETPLACE_REPO_URL:-https://perspikapps.github.io/vps/}"

up() {
    export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
    command -v kubectl >/dev/null 2>&1 || { zz-log e "[vps-setup] kubectl not found; run vps-k3s/run.sh first." && exit 1; }
    kubectl get deploy -n cattle-system rancher >/dev/null 2>&1 || zz-log w "[vps-setup] Rancher doesn't look installed yet (no cattle-system/rancher" \
        "deployment) - registering the catalog anyway; it'll show up under" \
        "Apps & Marketplace once Rancher is up."

    zz-log i "[vps-setup] Registering the ${MARKETPLACE_REPO_NAME} catalog (${MARKETPLACE_REPO_URL})..."
    yaml-render "$(dirname "$0")/helm/clusterrepo.yaml" MARKETPLACE_REPO_NAME="$MARKETPLACE_REPO_NAME" MARKETPLACE_REPO_URL="$MARKETPLACE_REPO_URL" | kubectl apply -f -

    zz-log s "[vps-setup] Catalog '${MARKETPLACE_REPO_NAME}' registered."
    zz-log s "[vps-setup] In Rancher: Apps & Marketplace -> Repositories, it should show up there" \
        "(may take a minute to sync). Install ArgoCD / Epinio from" \
        "Apps & Marketplace -> Charts once it does."
}

down() {
    export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
    command -v kubectl >/dev/null 2>&1 || { zz-log w "[vps-setup] kubectl not found; nothing to remove." && return 0; }
    kubectl delete clusterrepo "$MARKETPLACE_REPO_NAME" --ignore-not-found
    zz-log s "[vps-setup] Catalog '${MARKETPLACE_REPO_NAME}' removed (apps already installed from it are untouched)."
}

summary() {
    cat <<EOF
 Marketplace:         Apps & Marketplace -> Repositories in Rancher should
                       list "${MARKETPLACE_REPO_NAME}" (registered by the
                       vps-marketplace step) - install ArgoCD, Epinio, or
                       any other chart from this repo's catalog from
                       Apps & Marketplace -> Charts. See README's
                       "Rancher Marketplace" section.
EOF
}
