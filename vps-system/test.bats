#!/usr/bin/env bats
# Static checks for vps-system/run.sh and package.json - a live install
# needs a real root Ubuntu box, so this stops at syntax + shape (see
# this folder's README's "Tests" section, and ../tests/ for repo-wide checks).

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
DIR="$REPO_ROOT/vps-system"

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

@test "has no down() - a one-shot upgrade, nothing to undo" {
    ! grep -q '^down() {' "$DIR/run.sh"
}

@test "package.json bin entry matches the folder name" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.bin['vps-system'] === 'run.sh' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json declares vps.order as a number" {
    run node -e "const p = require('$DIR/package.json'); process.exit(typeof p.config.order === 'number' ? 0 : 1)"
    [ "$status" -eq 0 ]
}



@test "upgrades and unattended security upgrades cover apt, dnf and zypper" {
    grep -q 'zz-install -f -m' "$DIR/run.sh"
    ! grep -qE 'apt-get (update|upgrade)' "$DIR/run.sh"
    grep -q 'dnf-automatic' "$DIR/run.sh"
}
