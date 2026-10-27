#!/bin/sh
# Hermes: installs charts/hermes of this checkout with helm (see app-helm). Env vars: see README.
# A zz-setup step: configured by environment inputs (package.json config.inputs),
# run with up, down or summary as its first argument.

set -eu
zz-use zz-colors zz-log zz-step
# shellcheck disable=SC1091
. zz-colors

up() {
    [ -n "${HERMES_IMAGE_REPOSITORY:-}" ] || { zz-log e "HERMES_IMAGE_REPOSITORY is required: no official Hermes image exists (build one, see charts/hermes/README.md)." && exit 1; }
    jq -n --arg r "$HERMES_IMAGE_REPOSITORY" --arg t "${HERMES_IMAGE_TAG:-latest}" --arg s "${HERMES_ENV_SECRET:-}" \
        '{image: {repository: $r, tag: $t}, envFromSecretName: $s}' |
    app-helm up hermes --middlewares-key dashboard.ingress.middlewares --values-stdin
}

down() {
    app-helm down hermes
}

summary() {
    app-helm summary hermes
}

. zz-step
