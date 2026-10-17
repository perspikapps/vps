#!/usr/bin/env bats
# Static checks for vps-coder/run.sh and package.json - the install needs a
# live k3s cluster, so this stops at syntax + shape.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
DIR="$REPO_ROOT/vps-coder"

@test "run.sh parses as bash" {
    run bash -n "$DIR/run.sh"
    [ "$status" -eq 0 ]
}

@test "run.sh bootstraps zz-use and sources common" {
    grep -q 'zz-use "perspikapps/vps/vps-common' "$DIR/run.sh"
    grep -q '^\. vps-common$' "$DIR/run.sh"
}

@test "defines up(), down() and dispatches via dispatch_action" {
    grep -q '^up() {' "$DIR/run.sh"
    grep -q '^down() {' "$DIR/run.sh"
    grep -q 'dispatch_action "\$@"' "$DIR/run.sh"
}

@test "follows the Coder Rancher guide: bitnami postgres, coder-db-url secret, upstream chart" {
    grep -q 'bitnami/postgresql' "$DIR/run.sh"
    grep -q 'coder-db-url' "$DIR/run.sh"
    grep -q 'https://helm.coder.com/v2' "$DIR/run.sh"
    grep -q 'CODER_PG_CONNECTION_URL' "$DIR/run.sh"
}

@test "the database password is generated and stored, never a fixed value or a --set argument" {
    grep -q 'random_password' "$DIR/run.sh"
    grep -q 'vps_secret_set CODER_DB_PASSWORD' "$DIR/run.sh"
    ! grep -q 'auth.password=' "$DIR/run.sh"
}

@test "opt-in, depends on vps-rancher, ordered after it" {
    run node -e "
        const p = require('$DIR/package.json'), r = require('$REPO_ROOT/vps-rancher/package.json');
        process.exit(p.config.default === false && p.dependencies['@tomgrv/vps-rancher'] === '*' && p.config.order > r.config.order ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "exposed through the Traefik ingress, access URL and wildcard from the same domain (cookie scope)" {
    grep -q 'className: "traefik"' "$DIR/run.sh"
    grep -q 'wildcardHost' "$DIR/run.sh"
    grep -q 'http://coder.${WILDCARD}' "$DIR/run.sh"
    grep -q '\*\.${WILDCARD}' "$DIR/run.sh"
    ! grep -q 'patch_service_port' "$DIR/run.sh"
}

@test "fails early, naming ZZ_SETUP_REF, when the cached vps-common predates wildcard_domain" {
    grep -q 'declare -F wildcard_domain' "$DIR/run.sh"
    grep -q 'ZZ_SETUP_REF=<ref> zz-setup' "$DIR/run.sh"
}

@test "the Envbuilder template push is opt-in on a session token, never fails the install, token not on a command line" {
    grep -q 'kubernetes-devcontainer' "$DIR/run.sh"
    grep -q 'if \[\[ -n "\${CODER_SESSION_TOKEN:-}" \]\]' "$DIR/run.sh"
    grep -q '|| zz-log w' "$DIR/run.sh"
    ! grep -q -- '--token' "$DIR/run.sh"
    run node -e "const i = require('$DIR/package.json').config.inputs.CODER_SESSION_TOKEN; process.exit(i && i.required === false && i.secret === true ? 0 : 1)"
    [ "$status" -eq 0 ]
}
