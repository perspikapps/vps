#!/bin/sh
# app-cert-manager [-v version] - install cert-manager (with its CRDs) through Helm
# unless the deployment is already there, logging progress while it starts. A script,
# not a step: app-rancher (and any chart needing certificates) calls it.

set -eu
zz-use zz-colors zz-log zz-args kube-require helm-repo helm-install
# shellcheck disable=SC1091
. zz-colors

eval "$(
    zz-args "Install cert-manager unless it is already installed" "$0" "$@" <<help
v version version Chart version to pin (default: RANCHER_CERT_MANAGER_VERSION, else the latest)
help
)"

version=${version:-${RANCHER_CERT_MANAGER_VERSION:-}}

eval "$(kube-require)"

if kubectl get deploy -n cert-manager cert-manager >/dev/null 2>&1; then
    zz-log i "cert-manager already installed."
    exit 0
fi

zz-log i "Installing cert-manager..."
helm-repo jetstack https://charts.jetstack.io
# The unquoted version splits on spaces; a chart version has none.
# shellcheck disable=SC2086
helm-install -t 5m cert-manager cert-manager jetstack/cert-manager \
    --set crds.enabled=true \
    ${version:+--version $version} \
    --wait
