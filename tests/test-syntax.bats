#!/usr/bin/env bats
# Fast, dependency-free sanity checks: every script at least parses. The
# feature scripts themselves need root/a live k3s cluster/etc. to actually
# run, so this repo's test coverage stops at syntax + common/run.sh's pure
# logic (see test-common.bats) rather than attempting a full install here.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

@test "dispatch.sh: parses as POSIX sh" {
    run sh -n "$REPO_ROOT/dispatch.sh"
    [ "$status" -eq 0 ]
}

@test "every */run.sh parses as bash" {
    for f in "$REPO_ROOT"/*/run.sh; do
        run bash -n "$f"
        [ "$status" -eq 0 ]
    done
}

@test "every */run.sh bootstraps zz_use and sources common (except common/summary)" {
    for f in "$REPO_ROOT"/*/run.sh; do
        name="$(basename "$(dirname "$f")")"
        case "$name" in
        common) continue ;;
        esac
        grep -q 'zz_use "perspikapps/vps/common' "$f"
        grep -q '^\. common$' "$f"
    done
}

@test "every feature folder has a package.json with a name and vps.order" {
    for f in "$REPO_ROOT"/*/run.sh; do
        d="$(dirname "$f")"
        name="$(basename "$d")"
        case "$name" in
        common | summary) continue ;;
        esac
        [ -f "$d/package.json" ]
        run node -e "const p = require('$d/package.json'); if (!p.name || typeof p.vps.order !== 'number') process.exit(1)"
        [ "$status" -eq 0 ]
    done
}
