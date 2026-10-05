#!/usr/bin/env bats
# Repo-wide checks that don't belong to any single folder: invariants
# spanning every folder's run.sh or package.json. Per-folder syntax/shape
# (parses, zz_use/vps-common wiring, up()/down(), bin/vps.order/dependencies)
# lives in each folder's own <name>/test.bats - see this repo's README's
# "Tests" section - rather than being re-checked here in a loop over every
# folder. vps-setup's own orchestration logic (feature discovery,
# dependency resolution, flag parsing) is covered by vps-setup/test.bats,
# since that's the folder that owns it - there's no more root dispatch.sh
# to test here.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

@test "no root setup.sh - bootstrapping relies on tomgrv/scripts' own copy" {
    # See README's "Running vps-setup" and "Layout" sections: this repo
    # deliberately doesn't keep a copy of the generic zz_use bootstrapper,
    # so there's nothing here to duplicate/keep in sync.
    [ ! -e "$REPO_ROOT/setup.sh" ]
    for f in "$REPO_ROOT"/*/run.sh "$REPO_ROOT"/README.md; do
        ! grep -qE 'perspikapps/vps/[^ ]*setup\.sh' "$f"
    done
}

@test "package.json has no \"main\" field (no root entrypoint script to point at)" {
    run node -e "const p = require('$REPO_ROOT/package.json'); if ('main' in p) process.exit(1)"
    [ "$status" -eq 0 ]
}

@test "vps-common/run.sh no longer defines log/warn/die wrappers (call sites use zz_log directly)" {
    ! grep -qE '^(log|warn|die)\(\)' "$REPO_ROOT/vps-common/run.sh"
    for f in "$REPO_ROOT"/*/run.sh; do
        ! grep -qE '(^|[|&{;[:space:]])(log|warn|die) "' "$f"
    done
}

@test "no run.sh references the removed dispatch.sh" {
    for f in "$REPO_ROOT"/*/run.sh; do
        ! grep -q 'dispatch\.sh' "$f"
    done
}
