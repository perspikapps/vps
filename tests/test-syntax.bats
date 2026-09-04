#!/usr/bin/env bats
# Repo-wide checks that don't belong to any single folder: setup.sh
# itself, and invariants spanning every folder's run.sh or package.json.
# Per-folder syntax/shape (parses, zz_use/vps-common wiring, up()/down(),
# bin/vps.order/dependencies) now lives in each folder's own
# <name>/test.bats - see this repo's README's "Tests" section - rather
# than being re-checked here in a loop over every folder. vps-setup's own
# orchestration logic (feature discovery, dependency resolution, flag
# parsing) is covered by vps-setup/test.bats, since that's the folder
# that owns it - there's no more root dispatch.sh to test here.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

@test "setup.sh: parses as POSIX sh and is a bulk copy of tomgrv/scripts' own setup.sh" {
    # Deliberately identical, not just similar - see README's "Running
    # vps-setup" section: it's the same generic bootstrap utility,
    # duplicated here only for URL stability under this repo, defaulting
    # to bootstrapping the core zz_* bundle from tomgrv/scripts (ZZ_ORIGIN)
    # exactly as tomgrv/scripts' own copy does. Its generic package.json
    # "main"-field handoff is inert for this repo (no "main" field, see
    # the next test) - vps-setup is fetched and run as its own separate
    # step, never auto-execed by setup.sh.
    run sh -n "$REPO_ROOT/setup.sh"
    [ "$status" -eq 0 ]
    grep -q 'ZZ_ORIGIN="\${ZZ_ORIGIN:-tomgrv/scripts}"' "$REPO_ROOT/setup.sh"
    grep -q 'zz_use zz_update zz_colors zz_log' "$REPO_ROOT/setup.sh"
    ! grep -q 'exec ' "$REPO_ROOT/setup.sh"
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
