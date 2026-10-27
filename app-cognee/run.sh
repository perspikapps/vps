#!/bin/sh
# Cognee: installs charts/cognee of this checkout with helm (see app-helm). Env vars: see README.
# A zz-setup step: configured by environment inputs (package.json config.inputs),
# run with up, down or summary as its first argument.

set -eu
zz-use zz-colors zz-log zz-persist zz-step
# shellcheck disable=SC1091
. zz-colors

up() {
    local llm_key

    llm_key="$(zz-persist -S COGNEE_LLM_API_KEY "${COGNEE_LLM_API_KEY:-}")"
    [ -n "$llm_key" ] || { zz-log e "COGNEE_LLM_API_KEY is required: the container does not start without it." && exit 1; }
    jq -n --arg k "$llm_key" '{llmApiKey: $k}' |
    app-helm up cognee --middlewares-key ingress.middlewares --values-stdin
}

down() {
    app-helm down cognee
    zz-persist -S -q -u COGNEE_LLM_API_KEY
}

summary() {
    app-helm summary cognee
}

. zz-step
