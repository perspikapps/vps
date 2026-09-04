#!/usr/bin/env bats
# Static checks for vps-setup/ - not an installable step itself (excluded
# from its own feature discovery, like vps-common), so no vps.order to
# check. It orchestrates every *other* step, so a live run needs a real
# root Ubuntu box - see this folder's README's "Tests" section.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
DIR="$REPO_ROOT/vps-setup"

@test "run.sh parses as bash" {
    run bash -n "$DIR/run.sh"
    [ "$status" -eq 0 ]
}

@test "run.sh bootstraps zz_use and sources vps-common" {
    grep -q 'zz_use "perspikapps/vps/vps-common' "$DIR/run.sh"
    grep -q '^\. vps-common$' "$DIR/run.sh"
}

@test "run.sh fails fast instead of curling setup.sh itself" {
    grep -q 'command -v zz_use >/dev/null 2>&1 || { echo "zz_use not found on PATH - run this repo'"'"'s setup.sh first' "$DIR/run.sh"
    ! grep -q 'curl -fsSL.*setup\.sh.*| sh$' "$DIR/run.sh"
}

@test "run.sh sources steps.sh from its own folder" {
    grep -q '"\$REPO_ROOT/vps-setup/steps.sh"' "$DIR/run.sh"
}

@test "steps.sh parses as POSIX sh" {
    run sh -n "$DIR/steps.sh"
    [ "$status" -eq 0 ]
}

@test "run.sh excludes itself and vps-common from feature discovery" {
    grep -q 'vps-common | vps-setup' "$DIR/run.sh"
}

@test "package.json bin entry matches the folder name" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.bin['vps-setup'] === 'run.sh' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json depends on @tomgrv/vps-common" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.dependencies['@tomgrv/vps-common'] === '*' ? 0 : 1)"
    [ "$status" -eq 0 ]
}
