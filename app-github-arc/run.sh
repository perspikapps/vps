#!/bin/sh
# GitHub ARC: installs charts/github-arc of this checkout with helm (see app-helm). Env vars: see README.
# A zz-setup step: configured by environment inputs (package.json config.inputs),
# run with up, down or summary as its first argument.

set -eu
zz-use zz-colors zz-log zz-step
# shellcheck disable=SC1091
. zz-colors

up() {
    local v

    for v in GITHUB_ARC_CONFIG_URL GITHUB_ARC_APP_ID GITHUB_ARC_APP_INSTALLATION_ID GITHUB_ARC_APP_PRIVATE_KEY; do
        eval "[ -n \"\${$v:-}\" ]" || { zz-log e "${v} is required (see charts/github-arc/README.md)." && exit 1; }
    done
    jq -n --arg u "$GITHUB_ARC_CONFIG_URL" --arg i "$GITHUB_ARC_APP_ID" --arg n "$GITHUB_ARC_APP_INSTALLATION_ID" --arg k "$GITHUB_ARC_APP_PRIVATE_KEY" \
        '{"gha-runner-scale-set": {githubConfigUrl: $u, githubConfigSecret: {github_app_id: $i, github_app_installation_id: $n, github_app_private_key: $k}}}' |
    app-helm up github-arc --values-stdin
}

down() {
    app-helm down github-arc
}

summary() {
    app-helm summary github-arc --note "runners register against the URL above; target them with runs-on: [self-hosted, arc-runner-set]"
}

. zz-step
