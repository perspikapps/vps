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

@test "opt-in, depends on vps-rancher, ordered after it, with a private port" {
    run node -e "
        const p = require('$DIR/package.json'), r = require('$REPO_ROOT/vps-rancher/package.json');
        const port = p.config.ports.find(x => x.name === 'coder_http');
        process.exit(p.config.default === false && p.dependencies['@tomgrv/vps-rancher'] === '*'
            && p.config.order > r.config.order && port && port.access === 'private' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "no other step claims the coder_http port number" {
    run node -e "
        const fs = require('fs'), root = '$REPO_ROOT';
        const used = fs.readdirSync(root).filter(d => fs.existsSync(root + '/' + d + '/package.json') && d !== 'vps-coder')
            .flatMap(d => (require(root + '/' + d + '/package.json').config || {}).ports || []).map(x => x.port);
        process.exit(used.includes(require('$DIR/package.json').config.ports[0].port) ? 1 : 0)"
    [ "$status" -eq 0 ]
}
