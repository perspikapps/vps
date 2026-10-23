#!/usr/bin/env bats
# Repo-wide checks that don't belong to any single folder: invariants
# spanning every folder's run.sh or package.json. Per-folder syntax/shape
# (parses, zz-use/vps-common wiring, up()/down(), bin/vps.order/dependencies)
# lives in each folder's own <name>/test.bats - see this repo's README's
# "Tests" section - rather than being re-checked here in a loop over every
# folder. vps-setup's own orchestration logic (feature discovery,
# dependency resolution, flag parsing) is covered by vps-setup/test.bats,
# since that's the folder that owns it - there's no more root dispatch.sh
# to test here.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

@test "no root setup.sh - bootstrapping relies on tomgrv/scripts' own copy" {
    # See README's "Running vps-setup" and "Layout" sections: this repo
    # deliberately doesn't keep a copy of the generic zz-use bootstrapper,
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

@test "vps-common/run.sh no longer defines log/warn/die wrappers (call sites use zz-log directly)" {
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

@test "steps leave require_root to dispatch_action (up/down) - no explicit call left" {
    for f in "$REPO_ROOT"/vps-*/run.sh; do
        [[ "$f" == */vps-common/* || "$f" == */vps-setup/* ]] && continue
        ! grep -q '^\s*require_root$' "$f"
    done
}

@test "installer scripts are fetched with download_run, not through a predictable /tmp path" {
    ! grep -nE '/tmp/[a-z0-9.-]*(install|get-helm)[a-z0-9.-]*' "$REPO_ROOT"/vps-*/run.sh
}

@test "every step's summary action runs and prints its block" {
    stubs=$(mktemp -d)
    printf '#!/bin/sh\nexit 0\n' >"$stubs/zz-use"
    printf '#!/bin/sh\nshift; echo "$*"\n' >"$stubs/zz-log"
    : >"$stubs/zz-colors"
    ln -s "$REPO_ROOT/vps-common/run.sh" "$stubs/vps-common"
    chmod +x "$stubs"/zz-use "$stubs"/zz-log
    for step in cockpit k3s marketplace rancher security tailscale; do
        run env PATH="$stubs:$PATH" bash "$REPO_ROOT/vps-$step/run.sh" summary
        [ "$status" -eq 0 ]
        [ -n "$output" ]
    done
    rm -rf "$stubs"
}

@test "steps without something to report (system, an opt-in step not installed) print nothing for summary" {
    stubs=$(mktemp -d)
    printf '#!/bin/sh\nexit 0\n' >"$stubs/zz-use"
    printf '#!/bin/sh\nshift; echo "$*"\n' >"$stubs/zz-log"
    : >"$stubs/zz-colors"
    ln -s "$REPO_ROOT/vps-common/run.sh" "$stubs/vps-common"
    chmod +x "$stubs"/zz-use "$stubs"/zz-log
    for step in system dokploy cloudflare coder; do
        run env PATH="$stubs:$PATH" bash "$REPO_ROOT/vps-$step/run.sh" summary
        [ "$status" -eq 0 ]
        [ -z "$output" ]
    done
    rm -rf "$stubs"
}

@test "every step has its own config.order (the install order is a total order)" {
    run node -e "
        const fs = require('fs');
        const orders = fs.readdirSync('$REPO_ROOT').filter(d => fs.existsSync('$REPO_ROOT/' + d + '/package.json'))
            .map(d => require('$REPO_ROOT/' + d + '/package.json'))
            .filter(p => p.engines && p.engines['zz-setup']).map(p => p.config.order);
        process.exit(new Set(orders).size === orders.length ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "every input a package.json declares is documented in that folder's README" {
    for d in "$REPO_ROOT"/vps-*/; do
        for v in $(jq -r '(.config.inputs // {}) | keys[]' "$d/package.json"); do
            grep -q "\`$v\`" "$d/README.md"
        done
    done
}

@test "credentials go through vps_secret*: the old one-value files only appear as legacy arguments" {
    ! grep -nE '(echo|cat|rm -f|>)[^#]*/root/\.(cockpit-admin|rancher-bootstrap)' "$REPO_ROOT"/vps-*/run.sh | grep -v 'vps_secret'
}

@test "every run.sh is POSIX sh: #!/bin/sh and parses with dash (zz-setup conventions)" {
    for f in "$REPO_ROOT"/*/run.sh; do
        [ "$(head -n1 "$f")" = "#!/bin/sh" ]
        dash -n "$f"
    done
}
