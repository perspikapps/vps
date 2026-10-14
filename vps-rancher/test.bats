#!/usr/bin/env bats
# Static checks for vps-rancher/run.sh and package.json - a live install
# needs a real root Ubuntu box, so this stops at syntax + shape (see
# this folder's README's "Tests" section, and ../tests/ for repo-wide checks).

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
DIR="$REPO_ROOT/vps-rancher"

@test "run.sh parses as bash" {
    run bash -n "$DIR/run.sh"
    [ "$status" -eq 0 ]
}

@test "run.sh bootstraps zz-use and sources common" {
    grep -q 'zz-use "perspikapps/vps/vps-common' "$DIR/run.sh"
    grep -q '^\. vps-common$' "$DIR/run.sh"
}

@test "run.sh does not bootstrap zz-use itself (assumes setup.sh already ran)" {
    ! grep -q 'command -v zz-use' "$DIR/run.sh"
    ! grep -q 'curl -fsSL.*setup\.sh.*| sh$' "$DIR/run.sh"
}

@test "defines up() and dispatches via dispatch_action" {
    grep -q '^up() {' "$DIR/run.sh"
    grep -q 'dispatch_action "\$@"' "$DIR/run.sh"
}

@test "defines down()" {
    grep -q '^down() {' "$DIR/run.sh"
}

@test "package.json bin entry matches the folder name" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.bin['vps-rancher'] === 'run.sh' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json declares vps.order as a number" {
    run node -e "const p = require('$DIR/package.json'); process.exit(typeof p.vps.order === 'number' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json depends on @tomgrv/vps-common" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.dependencies['@tomgrv/vps-common'] === '*' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json depends on @tomgrv/vps-k3s" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.dependencies['@tomgrv/vps-k3s'] === '*' ? 0 : 1)"
    [ "$status" -eq 0 ]
}


@test "hostname and bootstrapPassword are passed as strings via a values file, not --set" {
    ! grep -q -- '--set bootstrapPassword' "$DIR/run.sh"
    ! grep -q -- '--set hostname' "$DIR/run.sh"
    grep -q -- '--values "\$VALUES_FILE"' "$DIR/run.sh"
}

@test "a numeric-looking bootstrap password stays a string in the values file" {
    command -v jq >/dev/null || skip "jq not installed"
    out=$(jq -n --arg hostname "1.2.3.4" --arg bootstrapPassword "12345678" \
        '{hostname: $hostname, bootstrapPassword: $bootstrapPassword}')
    [ "$(printf '%s' "$out" | jq -r '.bootstrapPassword | type')" = "string" ]
    [ "$(printf '%s' "$out" | jq -r '.bootstrapPassword')" = "12345678" ]
}
