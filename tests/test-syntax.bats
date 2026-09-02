#!/usr/bin/env bats
# Repo-wide checks that don't belong to any single folder: dispatch.sh/
# setup.sh themselves, and invariants spanning every folder's run.sh or
# package.json. Per-folder syntax/shape (parses, zz_use/common wiring,
# up()/down(), bin/vps.order/dependencies) now lives in each folder's own
# <name>/test.bats - see this repo's README's "Tests" section - rather
# than being re-checked here in a loop over every folder.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

@test "dispatch.sh: parses as POSIX sh" {
    run sh -n "$REPO_ROOT/dispatch.sh"
    [ "$status" -eq 0 ]
}

@test "dispatch.sh bootstraps zz_use once via setup.sh, not per-feature, forwarding args" {
    grep -q 'exec sh "\$REPO_ROOT/setup.sh" "\$@"' "$REPO_ROOT/dispatch.sh"
}

@test "setup.sh: parses as POSIX sh, delegates to tomgrv/scripts' own setup.sh, then execs this repo's main" {
    run sh -n "$REPO_ROOT/setup.sh"
    [ "$status" -eq 0 ]
    grep -q 'raw.githubusercontent.com/tomgrv/scripts' "$REPO_ROOT/setup.sh"
    grep -q '"main"' "$REPO_ROOT/setup.sh"
}

@test "package.json declares dispatch.sh as \"main\" (setup.sh's exec target)" {
    run node -e "const p = require('$REPO_ROOT/package.json'); if (p.main !== 'dispatch.sh') process.exit(1)"
    [ "$status" -eq 0 ]
}

@test "vps-common/run.sh no longer defines log/warn/die wrappers (call sites use zz_log directly)" {
    ! grep -qE '^(log|warn|die)\(\)' "$REPO_ROOT/vps-common/run.sh"
    for f in "$REPO_ROOT"/*/run.sh; do
        ! grep -qE '(^|[|&{;[:space:]])(log|warn|die) "' "$f"
    done
}

@test "dispatch.sh never treats vps-common/vps-summary as auto-enable dependency targets" {
    # dispatch.sh isn't designed to be sourced (it runs to completion as a
    # script), so this reproduces feature_deps()'s own filtering logic
    # rather than sourcing the real function: a dependency key only counts
    # if, once its npm scope is stripped the same way as feature_name()
    # (see dispatch.sh), it excludes vps-common/vps-summary AND names a real
    # <folder>/{package.json,run.sh} - folder names match workspace names
    # (see README's "One folder per feature"), so the npm scope is the
    # only prefix to strip.
    run bash -c "
        set -eu
        FEATURES_DIR='$REPO_ROOT'
        feature_deps() {
            jq -r '(.dependencies // {}) | keys[] | sub(\"^@tomgrv/\"; \"\")' \"\$1/package.json\" | grep -vxE 'vps-common|vps-summary' | while IFS= read -r dep; do
                [ -f \"\$FEATURES_DIR/\$dep/package.json\" ] && [ -f \"\$FEATURES_DIR/\$dep/run.sh\" ] && printf '%s\n' \"\$dep\"
            done
        }
        feature_deps '$REPO_ROOT/vps-rancher' | grep -qx vps-common && exit 1
        feature_deps '$REPO_ROOT/vps-rancher' | grep -qx vps-k3s || exit 1
        exit 0
    "
    [ "$status" -eq 0 ]
}
