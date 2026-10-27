#!/bin/sh
# Hermes: installs charts/hermes of this checkout with helm (see app-helm). Env vars: see README.
# A zz-setup step: configured by environment inputs (package.json config.inputs),
# run with up, down or summary as its first argument.

set -eu
zz-use zz-colors zz-log
# shellcheck disable=SC1091
. zz-colors

up() {
    local values

    [ -n "${HERMES_IMAGE_REPOSITORY:-}" ] || { zz-log e "HERMES_IMAGE_REPOSITORY is required: no official Hermes image exists (build one, see charts/hermes/README.md)." && exit 1; }
    values="$(mktemp)"
    jq -n --arg r "$HERMES_IMAGE_REPOSITORY" --arg t "${HERMES_IMAGE_TAG:-latest}" --arg s "${HERMES_ENV_SECRET:-}" \
        '{image: {repository: $r, tag: $t}, envFromSecretName: $s}' >"$values"
    app-helm up hermes --middlewares-key dashboard.ingress.middlewares --values "$values" || { rm -f "$values" && exit 1; }
    rm -f "$values"
}

down() {
    app-helm down hermes
}

summary() {
    app-helm summary hermes
}

case "${1:-}" in
    up | down) "$1" ;;
    summary) if command -v summary >/dev/null 2>&1; then summary; fi ;;
    *) zz-log e "Usage: $0 up|down|summary" && exit 1 ;;
esac
