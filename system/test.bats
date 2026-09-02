#!/usr/bin/env bats
# Static checks for system/run.sh and package.json - a live install
# needs a real root Ubuntu box, so this stops at syntax + shape (see
# this folder's README's "Tests" section, and ../tests/ for repo-wide checks).

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
DIR="$REPO_ROOT/system"

@test "run.sh parses as bash" {
    run bash -n "$DIR/run.sh"
    [ "$status" -eq 0 ]
}

@test "run.sh bootstraps zz_use and sources common" {
    grep -q 'zz_use "perspikapps/vps/common' "$DIR/run.sh"
    grep -q '^\. common$' "$DIR/run.sh"
}

@test "run.sh fails fast instead of curling setup.sh itself" {
    grep -q 'command -v zz_use >/dev/null 2>&1 || { echo "zz_use not found on PATH - run this repo'"'"'s setup.sh first' "$DIR/run.sh"
    ! grep -q 'curl -fsSL.*setup\.sh.*| sh$' "$DIR/run.sh"
}

@test "defines up() and dispatches via dispatch_action" {
    grep -q '^up() {' "$DIR/run.sh"
    grep -q 'dispatch_action "\$@"' "$DIR/run.sh"
}

@test "has no down() - a one-shot upgrade, nothing to undo" {
    ! grep -q '^down() {' "$DIR/run.sh"
}

@test "package.json bin entry matches the folder name" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.bin['system'] === 'run.sh' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json declares vps.order as a number" {
    run node -e "const p = require('$DIR/package.json'); process.exit(typeof p.vps.order === 'number' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json depends on common" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.dependencies['common'] === '*' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

