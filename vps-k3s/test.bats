#!/usr/bin/env bats
# Static checks for vps-k3s/run.sh and package.json - a live install
# needs a real root Ubuntu box, so this stops at syntax + shape (see
# this folder's README's "Tests" section, and ../tests/ for repo-wide checks).

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
DIR="$REPO_ROOT/vps-k3s"

@test "run.sh parses as POSIX sh" {
    run dash -n "$DIR/run.sh"
    [ "$status" -eq 0 ]
}

@test "run.sh sources nothing but zz-colors and calls the vps scripts instead" {
    grep -q '^\. zz-colors$' "$DIR/run.sh"
    [ -z "$(grep -E '^\s*(\.|source) ' "$DIR/run.sh" | grep -v '\. zz-colors')" ]
}

@test "run.sh does not bootstrap zz-use itself (assumes setup.sh already ran)" {
    ! grep -q 'command -v zz-use' "$DIR/run.sh"
    ! grep -q 'curl -fsSL.*setup\.sh.*| sh$' "$DIR/run.sh"
}

@test "defines up() and is a config.functions step" {
    grep -q '^up() {' "$DIR/run.sh"
    run node -e "const p = require('$DIR/package.json'); process.exit(p.config.functions === true ? 0 : 1)"
    [ "$status" -eq 0 ]
    ! grep -q 'dispatch_action\|zz-step' "$DIR/run.sh"
}

@test "defines down()" {
    grep -q '^down() {' "$DIR/run.sh"
}

@test "package.json bin entry matches the folder name" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.bin['vps-k3s'] === 'run.sh' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json declares vps.order as a number" {
    run node -e "const p = require('$DIR/package.json'); process.exit(typeof p.config.order === 'number' ? 0 : 1)"
    [ "$status" -eq 0 ]
}




@test "summary shows the public IP for the public Traefik ports, not the first local address" {
    sed -n '/^summary() {/,/^}/p' "$DIR/run.sh" | grep -q 'public-ip'
    ! sed -n '/^summary() {/,/^}/p' "$DIR/run.sh" | grep -q 'hostname -I'
}

@test "Traefik's chart values live in traefik-config.yaml, rendered by run.sh" {
    [ -f "$DIR/helm/traefik-config.yaml" ]
    grep -q 'kind: HelmChartConfig' "$DIR/helm/traefik-config.yaml"
    grep -q 'yaml-render "\$(dirname "\$0")/helm/traefik-config.yaml"' "$DIR/run.sh"
    ! grep -q 'kind: HelmChartConfig' "$DIR/run.sh"
}
