#!/bin/sh
# GitHub ARC: installs charts/github-arc of this checkout with helm (see app-helm). Env vars: see README.
# A zz-setup step: configured by environment inputs (package.json config.inputs),
# run with up, down or summary as its first argument.

set -eu
zz-use zz-colors zz-log
# shellcheck disable=SC1091
. zz-colors

up() {
    local values v

    for v in GITHUB_ARC_CONFIG_URL GITHUB_ARC_APP_ID GITHUB_ARC_APP_INSTALLATION_ID GITHUB_ARC_APP_PRIVATE_KEY; do
        eval "[ -n \"\${$v:-}\" ]" || { zz-log e "[vps-setup] ${v} is required (see charts/github-arc/README.md)." && exit 1; }
    done
    values="$(mktemp)"
    jq -n --arg u "$GITHUB_ARC_CONFIG_URL" --arg i "$GITHUB_ARC_APP_ID" --arg n "$GITHUB_ARC_APP_INSTALLATION_ID" --arg k "$GITHUB_ARC_APP_PRIVATE_KEY" \
        '{"gha-runner-scale-set": {githubConfigUrl: $u, githubConfigSecret: {github_app_id: $i, github_app_installation_id: $n, github_app_private_key: $k}}}' >"$values"
    app-helm up github-arc --values "$values" || { rm -f "$values" && exit 1; }
    rm -f "$values"
}

down() {
    app-helm down github-arc
}

summary() {
    app-helm summary github-arc --note "runners register against the URL above; target them with runs-on: [self-hosted, arc-runner-set]"
}

case "${1:-}" in
    up | down) "$1" ;;
    summary) if command -v summary >/dev/null 2>&1; then summary; fi ;;
    *) zz-log e "Usage: $0 up|down|summary" && exit 1 ;;
esac
