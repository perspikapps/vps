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

@test "menus only run on a terminal and can be switched off with ACCESS_MENU" {
    grep -q 'ACCESS_MENU:-true' "$DIR/run.sh"
    grep -q '\[ -t 0 \] || (: </dev/tty)' "$DIR/run.sh"
}

@test "runs after the internal network and before k3s, with the DNS inputs declared" {
    run node -e "const p = require('$DIR/package.json'); const t = require('$REPO_ROOT/vps-tailscale/package.json'); const k = require('$REPO_ROOT/vps-k3s/package.json'); process.exit(p.bin['vps-access'] === 'run.sh' && p.config.order > t.config.order && p.config.order < k.config.order && p.config.inputs.ACCESS_INTERNAL_DOMAIN && p.config.inputs.ACCESS_MENU ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "every service declaring config.visibility defaults to public or internal" {
    run node -e "const fs = require('fs'); const bad = fs.readdirSync('$REPO_ROOT').filter(d => fs.existsSync('$REPO_ROOT/' + d + '/package.json')).map(d => require('$REPO_ROOT/' + d + '/package.json')).filter(p => p.config && p.config.visibility && !['public', 'internal'].includes(p.config.visibility)); process.exit(bad.length ? 1 : 0)"
    [ "$status" -eq 0 ]
}

@test "summary spells out the rule, both domains and the public, internal and local paragraph" {
    grep -q 'each service is public OR internal, never both' "$DIR/run.sh"
    grep -q '^domain_line() {' "$DIR/run.sh"
    grep -q '^scope_services() {' "$DIR/run.sh"
    grep -q 'does NOT resolve' "$DIR/run.sh"
    grep -q 'vps-network summary-block' "$DIR/run.sh"
}

@test "ACCESS_EXTERNAL_DOMAIN is validated here, saved for vps-network's external-domain, and optional" {
    grep -q '^validate_external() {' "$DIR/run.sh"
    grep -q 'vps-network set-external-domain' "$DIR/run.sh"
    run node -e "const i = require('$DIR/package.json').config.inputs.ACCESS_EXTERNAL_DOMAIN; process.exit(i && i.required === false ? 0 : 1)"
    [ "$status" -eq 0 ]
}
