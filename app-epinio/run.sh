#!/bin/sh
# Epinio: installs charts/epinio of this checkout with helm (see app-helm). Env vars: see README.
# A zz-setup step: configured by environment inputs (package.json config.inputs),
# run with up, down or summary as its first argument.

set -eu
zz-use zz-colors zz-log zz-persist zz-step
# shellcheck disable=SC1091
. zz-colors

up() {
    local password

    password="$(zz-persist -S -g 24 EPINIO_ADMIN_PASSWORD "${EPINIO_ADMIN_PASSWORD:-}")"
    jq -n --arg p "$password" '{epinio: {api: {adminPassword: $p}}}' |
    app-helm up epinio --values-stdin
}

down() {
    app-helm down epinio
    zz-persist -S -q -u EPINIO_ADMIN_PASSWORD
}

summary() {
    app-helm summary epinio --note "user: admin" --note "password: $(zz-persist -S -r -v 'not set - run app-epinio/run.sh' EPINIO_ADMIN_PASSWORD)"
}

. zz-step
