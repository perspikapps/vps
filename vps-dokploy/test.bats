#!/usr/bin/env bats
# Static checks for vps-dokploy/run.sh and package.json - a live install
# needs a real root Ubuntu box with Docker, so this stops at syntax + shape
# (see this folder's README's "Tests" section, and ../tests/ for repo-wide checks).

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
DIR="$REPO_ROOT/vps-dokploy"

@test "run.sh parses as POSIX sh" {
    run dash -n "$DIR/run.sh"
    [ "$status" -eq 0 ]
}

@test "run.sh sources nothing but zz-colors and calls the vps scripts instead" {
    grep -q '^\. zz-colors$' "$DIR/run.sh"
    [ -z "$(grep -E '^\s*(\.|source) ' "$DIR/run.sh" | grep -v '\. zz-colors')" ]
}

@test "run.sh does not bootstrap zz-use itself (assumes setup.sh already ran)" {
    ! grep -q 'command -v zz-use' "$DIR/run.sh"
    ! grep -q 'curl -fsSL.*setup\.sh.*| sh$' "$DIR/run.sh"
}

@test "defines up() and dispatches its action" {
    grep -q '^up() {' "$DIR/run.sh"
    grep -q '^case "\${1:-}" in' "$DIR/run.sh"
    ! grep -q 'dispatch_action\|zz-step' "$DIR/run.sh"
}

@test "defines down()" {
    grep -q '^down() {' "$DIR/run.sh"
}

@test "refuses to run next to k3s and over a foreign swarm (the installer would reset it)" {
    grep -q 'command -v k3s' "$DIR/run.sh"
    grep -q 'Swarm.LocalNodeState' "$DIR/run.sh"
}

@test "the installer is fetched with zz-install -u -x, not piped from curl" {
    grep -q 'zz-install -u "\$DOKPLOY_INSTALL_URL" -x bash' "$DIR/run.sh"
    ! grep -qE 'curl[^#]*\| *(ba)?sh' "$DIR/run.sh"
}


@test "the admin port is guarded by vps-security's shared FORWARD guard, not a copy of it" {
    grep -q '^    "\$vps_network" reapply-guard$' "$DIR/run.sh"
    ! grep -qE '^[[:space:]]*iptables ' "$DIR/run.sh"
}

@test "package.json bin entry matches the folder name" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.bin['vps-dokploy'] === 'run.sh' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json declares vps.order as a number" {
    run node -e "const p = require('$DIR/package.json'); process.exit(typeof p.config.order === 'number' ? 0 : 1)"
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
