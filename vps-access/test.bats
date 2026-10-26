#!/usr/bin/env bats
# Static checks for vps-access/run.sh and package.json - the menus need a terminal
# and a live host, so this stops at syntax + shape (see ../tests/ for repo-wide checks).

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
DIR="$REPO_ROOT/vps-access"

@test "run.sh parses as POSIX sh" {
    run dash -n "$DIR/run.sh"
    [ "$status" -eq 0 ]
}

@test "defines up() and down() and dispatches up, down and summary" {
    grep -q '^up() {' "$DIR/run.sh"
    grep -q '^down() {' "$DIR/run.sh"
    grep -q '^case "\${1:-}" in' "$DIR/run.sh"
}

@test "menus only run on a terminal and can be switched off with VPS_ACCESS_MENU" {
    grep -q 'VPS_ACCESS_MENU:-true' "$DIR/run.sh"
    grep -q '\[ -t 0 \]' "$DIR/run.sh"
}

@test "runs after the private network and before k3s, with the DNS inputs declared" {
    run node -e "const p = require('$DIR/package.json'); const t = require('$REPO_ROOT/vps-tailscale/package.json'); const k = require('$REPO_ROOT/vps-k3s/package.json'); process.exit(p.bin['vps-access'] === 'run.sh' && p.config.order > t.config.order && p.config.order < k.config.order && p.config.inputs.INTERNAL_DOMAIN && p.config.inputs.VPS_ACCESS_MENU ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "every service declaring config.visibility defaults to public or internal" {
    run node -e "const fs = require('fs'); const bad = fs.readdirSync('$REPO_ROOT').filter(d => fs.existsSync('$REPO_ROOT/' + d + '/package.json')).map(d => require('$REPO_ROOT/' + d + '/package.json')).filter(p => p.config && p.config.visibility && !['public', 'internal'].includes(p.config.visibility)); process.exit(bad.length ? 1 : 0)"
    [ "$status" -eq 0 ]
}
