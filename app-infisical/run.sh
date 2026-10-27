#!/bin/sh
# Infisical: installs charts/infisical of this checkout with helm (see app-helm). Env vars: see README.
# A zz-setup step: configured by environment inputs (package.json config.inputs),
# run with up, down or summary as its first argument.

set -eu
zz-use zz-colors zz-log zz-persist
# shellcheck disable=SC1091
. zz-colors

up() {
    local values domain host enc auth

    domain="$(vps-network access-domain public)" || exit 1
    [ -n "$domain" ] || { zz-log e "[vps-setup] No domain: set SYSTEM_EXTERNAL_DOMAIN." && exit 1; }
    host="infisical.${domain}"
    enc="$(zz-persist -f "$SYSTEM_SECRETS_FILE" -r INFISICAL_ENCRYPTION_KEY | grep . || openssl rand -hex 16)"
    auth="$(zz-persist -f "$SYSTEM_SECRETS_FILE" -r INFISICAL_AUTH_SECRET | grep . || openssl rand -base64 32)"
    zz-persist -s -f "$SYSTEM_SECRETS_FILE" INFISICAL_ENCRYPTION_KEY "$enc" >/dev/null
    zz-persist -s -f "$SYSTEM_SECRETS_FILE" INFISICAL_AUTH_SECRET "$auth" >/dev/null
    # the root credentials Secret the chart requires, in the release namespace
    kubectl create namespace infisical --dry-run=client -o yaml | kubectl apply -f -
    kubectl -n infisical create secret generic infisical-secrets \
        --from-literal=ENCRYPTION_KEY="$enc" --from-literal=AUTH_SECRET="$auth" --from-literal=SITE_URL="http://${host}" \
        --dry-run=client -o yaml | kubectl apply -f -
    values="$(mktemp)"
    jq -n --arg h "$host" '{"infisical-standalone": {ingress: {hostName: $h}}}' >"$values"
    app-helm up infisical --values "$values" || { rm -f "$values" && exit 1; }
    rm -f "$values"
}

down() {
    app-helm down infisical
    zz-persist -q -f "$SYSTEM_SECRETS_FILE" -u INFISICAL_ENCRYPTION_KEY
    zz-persist -q -f "$SYSTEM_SECRETS_FILE" -u INFISICAL_AUTH_SECRET
}

summary() {
    app-helm summary infisical --note "root credentials: Secret infisical-secrets (namespace infisical); keys saved to the secrets file"
}

case "${1:-}" in
    up | down) "$1" ;;
    summary) if command -v summary >/dev/null 2>&1; then summary; fi ;;
    *) zz-log e "Usage: $0 up|down|summary" && exit 1 ;;
esac
