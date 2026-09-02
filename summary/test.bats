#!/usr/bin/env bats
# Static checks for summary/ - not an installable step (excluded from
# dispatch.sh's feature discovery), so no up()/down()/vps.order to check.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
DIR="$REPO_ROOT/summary"

@test "run.sh parses as bash" {
    run bash -n "$DIR/run.sh"
    [ "$status" -eq 0 ]
}

@test "run.sh bootstraps zz_use and sources common" {
    grep -q 'zz_use "perspikapps/vps/common' "$DIR/run.sh"
    grep -q '^\. common$' "$DIR/run.sh"
}

@test "dispatch-steps.sh parses as POSIX sh" {
    run sh -n "$DIR/dispatch-steps.sh"
    [ "$status" -eq 0 ]
}

@test "package.json bin entry matches the folder name" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.bin['summary'] === 'run.sh' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json depends on @tomgrv/vps-common" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.dependencies['@tomgrv/vps-common'] === '*' ? 0 : 1)"
    [ "$status" -eq 0 ]
}
