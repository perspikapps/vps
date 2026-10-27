#!/bin/sh
# Epinio: installs charts/epinio of this checkout with helm (see app-helm). Env vars: see README.
# A zz-setup step: configured by environment inputs (package.json config.inputs),
# run with up, down or summary as its first argument.

set -eu
zz-use zz-colors zz-log zz-persist
# shellcheck disable=SC1091
. zz-colors

up() {
    local values password

    password="$(zz-persist -f "$VPS_SECRETS_FILE" -s -g 24 EPINIO_ADMIN_PASSWORD "${EPINIO_ADMIN_PASSWORD:-}")"
    values="$(mktemp)"
    jq -n --arg p "$password" '{epinio: {api: {adminPassword: $p}}}' >"$values"
    app-helm up epinio --values "$values" || { rm -f "$values" && exit 1; }
    rm -f "$values"
}

down() {
    app-helm down epinio
    zz-persist -q -f "$VPS_SECRETS_FILE" -u EPINIO_ADMIN_PASSWORD
}

summary() {
    app-helm summary epinio --note "user: admin" --note "password: $(zz-persist -f "$VPS_SECRETS_FILE" -r EPINIO_ADMIN_PASSWORD | grep . || echo 'not set - run app-epinio/run.sh')"
}

case "${1:-}" in
    up | down) "$1" ;;
    summary) if command -v summary >/dev/null 2>&1; then summary; fi ;;
    *) zz-log e "Usage: $0 up|down|summary" && exit 1 ;;
esac
