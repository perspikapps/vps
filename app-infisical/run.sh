#!/bin/sh
# Infisical: installs charts/infisical of this checkout with helm (see app-helm). Env vars: see README.
# A zz-setup step: configured by environment inputs (package.json config.inputs),
# run with up, down or summary as its first argument.

set -eu
zz-use zz-colors zz-log zz-persist zz-step
# shellcheck disable=SC1091
. zz-colors

up() {
    local domain host enc auth

    domain="$(vps-network access-domain public)" || exit 1
    [ -n "$domain" ] || { zz-log e "No domain: set SYSTEM_EXTERNAL_DOMAIN." && exit 1; }
    host="infisical.${domain}"
    enc="$(zz-persist -S -g 32 -t hex INFISICAL_ENCRYPTION_KEY)"
    auth="$(zz-persist -S -g 44 INFISICAL_AUTH_SECRET)"
    # the root credentials Secret the chart requires, in the release namespace
    kubectl create namespace infisical --dry-run=client -o yaml | kubectl apply -f -
    kubectl -n infisical create secret generic infisical-secrets \
        --from-literal=ENCRYPTION_KEY="$enc" --from-literal=AUTH_SECRET="$auth" --from-literal=SITE_URL="http://${host}" \
        --dry-run=client -o yaml | kubectl apply -f -
    jq -n --arg h "$host" '{"infisical-standalone": {ingress: {hostName: $h}}}' |
    app-helm up infisical --values-stdin
}

down() {
    app-helm down infisical
    zz-persist -S -q -u "INFISICAL_ENCRYPTION_KEY INFISICAL_AUTH_SECRET"
}

summary() {
    app-helm summary infisical --note "root credentials: Secret infisical-secrets (namespace infisical); keys saved to the secrets file"
}

. zz-step
