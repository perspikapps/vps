#!/bin/sh
# Registers this repo's Helm chart catalog as a Rancher Apps &
# Marketplace repository. Env vars: see README.

set -eu
zz-use "perspikapps/vps/vps-common@${ZZ_SETUP_REF:-main}"
# shellcheck disable=SC1091
. vps-common

MARKETPLACE_REPO_NAME="${MARKETPLACE_REPO_NAME:-perspikapps-vps}"
MARKETPLACE_REPO_URL="${MARKETPLACE_REPO_URL:-https://perspikapps.github.io/vps/}"

up() {
    export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
    command_exists kubectl || { zz-log e "[vps-setup] kubectl not found; run vps-k3s/run.sh first." && exit 1; }
    kubectl get deploy -n cattle-system rancher >/dev/null 2>&1 || zz-log w "[vps-setup] Rancher doesn't look installed yet (no cattle-system/rancher" \
        "deployment) - registering the catalog anyway; it'll show up under" \
        "Apps & Marketplace once Rancher is up."

    zz-log i "[vps-setup] Registering the ${MARKETPLACE_REPO_NAME} catalog (${MARKETPLACE_REPO_URL})..."
    render_yaml "$(dirname "$0")/helm/clusterrepo.yaml" MARKETPLACE_REPO_NAME MARKETPLACE_REPO_URL | kubectl apply -f -

    ok "Catalog '${MARKETPLACE_REPO_NAME}' registered."
    ok "In Rancher: Apps & Marketplace -> Repositories, it should show up there" \
        "(may take a minute to sync). Install ArgoCD / Epinio from" \
        "Apps & Marketplace -> Charts once it does."
}

down() {
    export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
    command_exists kubectl || { zz-log w "[vps-setup] kubectl not found; nothing to remove." && return 0; }
    kubectl delete clusterrepo "$MARKETPLACE_REPO_NAME" --ignore-not-found
    ok "Catalog '${MARKETPLACE_REPO_NAME}' removed (apps already installed from it are untouched)."
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

dispatch_action "$@"
