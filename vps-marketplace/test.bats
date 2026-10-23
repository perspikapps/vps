#!/usr/bin/env bats
# Static checks for vps-marketplace/run.sh and package.json - a live install
# needs a real root Ubuntu box with Rancher already up, so this stops at
# syntax + shape (see this folder's README's "Tests" section, and
# ../tests/ for repo-wide checks).

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
DIR="$REPO_ROOT/vps-marketplace"

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

@test "defines up() and dispatches its action" {
    grep -q '^up() {' "$DIR/run.sh"
    grep -q '^case "\${1:-}" in' "$DIR/run.sh"
    ! grep -q 'dispatch_action\|zz-step' "$DIR/run.sh"
}

@test "defines down()" {
    grep -q '^down() {' "$DIR/run.sh"
}

@test "package.json bin entry matches the folder name" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.bin['vps-marketplace'] === 'run.sh' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json declares vps.order as a number" {
    run node -e "const p = require('$DIR/package.json'); process.exit(typeof p.config.order === 'number' ? 0 : 1)"
    [ "$status" -eq 0 ]
}


@test "package.json depends on @tomgrv/vps-rancher" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.dependencies['@tomgrv/vps-rancher'] === '*' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "the ClusterRepo manifest lives in helm/clusterrepo.yaml, rendered by run.sh" {
    [ -f "$DIR/helm/clusterrepo.yaml" ]
    grep -q 'kind: ClusterRepo' "$DIR/helm/clusterrepo.yaml"
    grep -q 'yaml-render "\$(dirname "\$0")/helm/clusterrepo.yaml"' "$DIR/run.sh"
    ! grep -q 'kind: ClusterRepo' "$DIR/run.sh"
}
