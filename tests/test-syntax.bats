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

@test "every run.sh bootstraps zz_use via this repo's own setup.sh, not a duplicated tomgrv/scripts URL" {
    for f in "$REPO_ROOT"/*/run.sh; do
        grep -q 'command -v zz_use >/dev/null 2>&1 || curl -fsSL "${VPS_SETUP_URL:-https://raw.githubusercontent.com/perspikapps/vps/main/setup.sh}" | sh' "$f"
        ! grep -q 'raw.githubusercontent.com/tomgrv/scripts' "$f"
    done
}

@test "setup.sh: parses as POSIX sh and delegates to tomgrv/scripts' own setup.sh" {
    run sh -n "$REPO_ROOT/setup.sh"
    [ "$status" -eq 0 ]
    grep -q 'raw.githubusercontent.com/tomgrv/scripts' "$REPO_ROOT/setup.sh"
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

@test "every folder's package.json has a bin entry matching its own folder name" {
    # zz_use has no notion of "bin" - it always installs <name>/run.sh
    # under the literal folder name <name> it was asked for - so the "bin"
    # entry must match the folder name exactly, not (necessarily) the
    # feature's own package.json "name" field. This is why vps-tailscale/
    # is named that instead of tailscale/ - see README's "One folder per
    # feature".
    for f in "$REPO_ROOT"/*/run.sh; do
        d="$(dirname "$f")"
        name="$(basename "$d")"
        run node -e "const p = require('$d/package.json'); if (p.bin['$name'] !== 'run.sh') process.exit(1)"
        [ "$status" -eq 0 ]
    done
}

@test "no feature's package.json bin name is the bare 'tailscale'" {
    # tailscale/run.sh's folder was renamed to vps-tailscale/ specifically
    # to avoid zz_use ever installing it under the same name as the real
    # tailscale CLI it calls internally - guard against that regressing.
    for f in "$REPO_ROOT"/*/run.sh; do
        d="$(dirname "$f")"
        run node -e "const p = require('$d/package.json'); if ('tailscale' in p.bin) process.exit(1)"
        [ "$status" -eq 0 ]
    done
}

@test "every feature depends on @tomgrv/vps-common (except common/summary)" {
    for f in "$REPO_ROOT"/*/run.sh; do
        d="$(dirname "$f")"
        name="$(basename "$d")"
        case "$name" in
        common | summary) continue ;;
        esac
        run node -e "const p = require('$d/package.json'); if (p.dependencies['@tomgrv/vps-common'] !== '*') process.exit(1)"
        [ "$status" -eq 0 ]
    done
}

@test "dispatch.sh never treats common/summary as auto-enable dependency targets" {
    # dispatch.sh isn't designed to be sourced (it runs to completion as a
    # script), so this reproduces feature_deps()'s own filtering logic
    # rather than sourcing the real function.
    run bash -c "
        set -eu
        pkg_deps() {
            awk '
                /\"dependencies\"[[:space:]]*:[[:space:]]*\{/ { infields = 1; next }
                infields && /\}/ { infields = 0 }
                infields { print }
            ' \"\$1\" | sed -n 's/^[[:space:]]*\"@tomgrv\\/vps-\\([a-zA-Z0-9_-]*\\)\".*/\\1/p'
        }
        feature_deps() { pkg_deps \"\$1/package.json\" | grep -vxE 'common|summary'; }
        feature_deps '$REPO_ROOT/rancher' | grep -qx common && exit 1
        feature_deps '$REPO_ROOT/rancher' | grep -qx k3s || exit 1
        exit 0
    "
    [ "$status" -eq 0 ]
}
