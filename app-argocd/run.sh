#!/bin/sh
# ArgoCD: installs charts/argocd of this checkout with helm (see app-helm). Env vars: see README.
# A zz-setup step: configured by environment inputs (package.json config.inputs),
# run with up, down or summary as its first argument.

set -eu
zz-use zz-colors zz-log
# shellcheck disable=SC1091
. zz-colors

up() {
    app-helm up argocd --middlewares-key ingress.middlewares
}

down() {
    app-helm down argocd
}

summary() {
    app-helm summary argocd --note "user: admin" --note "password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

case "${1:-}" in
    up | down) "$1" ;;
    summary) if command -v summary >/dev/null 2>&1; then summary; fi ;;
    *) zz-log e "Usage: $0 up|down|summary" && exit 1 ;;
esac
