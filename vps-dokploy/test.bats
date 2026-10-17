#!/usr/bin/env bats
# Static checks for vps-dokploy/run.sh and package.json - a live install
# needs a real root Ubuntu box with Docker, so this stops at syntax + shape
# (see this folder's README's "Tests" section, and ../tests/ for repo-wide checks).

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
DIR="$REPO_ROOT/vps-dokploy"

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

@test "refuses to run next to k3s and over a foreign swarm (the installer would reset it)" {
    grep -q 'command_exists k3s' "$DIR/run.sh"
    grep -q 'Swarm.LocalNodeState' "$DIR/run.sh"
}

@test "the installer is fetched with download_run, not piped from curl" {
    grep -q 'download_run "\$DOKPLOY_INSTALL_URL" bash' "$DIR/run.sh"
    ! grep -qE 'curl[^#]*\| *(ba)?sh' "$DIR/run.sh"
}

@test "the generated guard script parses as sh" {
    sed -n "/<<'GUARD'/,/^GUARD$/p" "$DIR/run.sh" | sed '1d;$d' >"$BATS_TEST_TMPDIR/guard.sh"
    [ -s "$BATS_TEST_TMPDIR/guard.sh" ]
    run sh -n "$BATS_TEST_TMPDIR/guard.sh"
    [ "$status" -eq 0 ]
}

@test "package.json bin entry matches the folder name" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.bin['vps-dokploy'] === 'run.sh' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json declares vps.order as a number" {
    run node -e "const p = require('$DIR/package.json'); process.exit(typeof p.config.order === 'number' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json depends on @tomgrv/vps-common only (no k3s: the two are exclusive)" {
    run node -e "const p = require('$DIR/package.json'); process.exit(Object.keys(p.dependencies).join() === '@tomgrv/vps-common' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json declares the k3s conflict, so zz-setup aborts before any step runs" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.config.conflicts.includes('vps-k3s') ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json is opt-in (default false), since a default run installs k3s on the same ports" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.config.default === false ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json keeps the admin UI private and the ingress public" {
    run node -e "
        const ports = Object.fromEntries(require('$DIR/package.json').config.ports.map(p => [p.name, p]));
        process.exit(ports.dokploy_ui.access === 'private' && ports.dokploy_ui.port === 3000
            && ports.dokploy_http.access === 'public' && ports.dokploy_https.access === 'public' ? 0 : 1)"
    [ "$status" -eq 0 ]
}
