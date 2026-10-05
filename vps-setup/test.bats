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

@test "run.sh does not bootstrap zz_use itself (assumes setup.sh already ran)" {
    ! grep -q 'command -v zz_use' "$DIR/run.sh"
    ! grep -q 'curl -fsSL.*setup\.sh.*| sh$' "$DIR/run.sh"
}

@test "run.sh builds its interactive menu with zz_menu in cycle mode" {
    grep -q 'zz_use .*zz_menu' "$DIR/run.sh"
    grep -q 'zz_menu -t "VPS setup menu" -c "skip,up,down"' "$DIR/run.sh"
}

@test "steps.sh lists feature inputs in a zz_menu and asks values with zz_prompt" {
    grep -q 'zz_use .*zz_prompt' "$DIR/run.sh"
    grep -q 'zz_menu -t "Feature inputs"' "$DIR/steps.sh"
    grep -q 'zz_prompt' "$DIR/steps.sh"
}

@test "steps.sh never prints an input's current value in the inputs menu" {
    ! grep -q '\[\$current\]' "$DIR/steps.sh"
}

@test "steps.sh persists each answered input via zz_persist and loads them back" {
    grep -q 'zz_use .*zz_persist' "$DIR/run.sh"
    grep -q '\. "\$envfile"' "$DIR/steps.sh"
    grep -F -q "zz_persist -f \"\$envfile\" \"\$choice\" \"'\$answer_quoted'\"" "$DIR/steps.sh"
}

@test "steps.sh single-quotes a persisted answer so spaces/metacharacters survive sourcing" {
    # An SSH key or similar value with embedded spaces, written unquoted by
    # zz_persist, would corrupt the env file on the next ". \$envfile" - see
    # the comment right above the zz_persist call.
    grep -F -q 'answer_quoted=' "$DIR/steps.sh"
    grep -F -q "sed \"s/'/'" "$DIR/steps.sh"
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
