#!/usr/bin/env bats
# Static checks for vps-cockpit/run.sh and package.json - a live install
# needs a real root Ubuntu box, so this stops at syntax + shape (see
# this folder's README's "Tests" section, and ../tests/ for repo-wide checks).

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
DIR="$REPO_ROOT/vps-cockpit"

@test "run.sh parses as POSIX sh" {
    run dash -n "$DIR/run.sh"
    [ "$status" -eq 0 ]
}

@test "run.sh sources the sibling vps-common, else the one zz-use fetches" {
    grep -q 'zz-use "perspikapps/vps/vps-common' "$DIR/run.sh"
    grep -q '^\. "\$common"$' "$DIR/run.sh"
}

@test "run.sh does not bootstrap zz-use itself (assumes setup.sh already ran)" {
    ! grep -q 'command -v zz-use' "$DIR/run.sh"
    ! grep -q 'curl -fsSL.*setup\.sh.*| sh$' "$DIR/run.sh"
}

@test "defines up() and ends with . zz-step" {
    grep -q '^up() {' "$DIR/run.sh"
    grep -q '^\. zz-step$' "$DIR/run.sh"
}

@test "defines down()" {
    grep -q '^down() {' "$DIR/run.sh"
}

@test "package.json bin entry matches the folder name" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.bin['vps-cockpit'] === 'run.sh' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json declares vps.order as a number" {
    run node -e "const p = require('$DIR/package.json'); process.exit(typeof p.config.order === 'number' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json depends on @tomgrv/vps-common" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.dependencies['@tomgrv/vps-common'] === '*' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

