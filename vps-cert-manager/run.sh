#!/bin/sh
# vps-cert-manager [-v version] - install cert-manager (with its CRDs) through Helm
# unless the deployment is already there, logging progress while it starts. A script,
# not a step: vps-rancher (and any chart needing certificates) calls it.

set -eu
zz-use zz-colors zz-log zz-args kube-progress
# shellcheck disable=SC1091
. zz-colors

eval "$(
    zz-args "Install cert-manager unless it is already installed" "$0" "$@" <<help
v version version Chart version to pin (default: CERT_MANAGER_VERSION, else the latest)
help
)"

version=${version:-${CERT_MANAGER_VERSION:-}}

if kubectl get deploy -n cert-manager cert-manager >/dev/null 2>&1; then
    zz-log i "cert-manager already installed."
    exit 0
fi

zz-log i "Installing cert-manager..."
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo update >/dev/null
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
# The unquoted version splits on spaces; a chart version has none.
# shellcheck disable=SC2086
kube-progress cert-manager "cert-manager install" \
    helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --set crds.enabled=true \
    ${version:+--version $version} \
    --wait --timeout 5m
