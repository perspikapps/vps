#!/usr/bin/env bats
# Static checks for svc-cloudflare/run.sh and package.json - a live install
# needs a real root Ubuntu box and a Cloudflare tunnel, so this stops at
# syntax + shape (see ../tests/ for repo-wide checks).

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
DIR="$REPO_ROOT/svc-cloudflare"

@test "run.sh parses as bash" {
    run dash -n "$DIR/run.sh"
    [ "$status" -eq 0 ]
}

@test "run.sh sources nothing but zz-colors and calls the vps scripts instead" {
    grep -q '^\. zz-colors$' "$DIR/run.sh"
    [ -z "$(grep -E '^\s*(\.|source) ' "$DIR/run.sh" | grep -v '\. zz-colors')" ]
}

@test "defines up(), down() and dispatches its action" {
    grep -q '^up() {' "$DIR/run.sh"
    grep -q '^down() {' "$DIR/run.sh"
    grep -q '^case "\${1:-}" in' "$DIR/run.sh"
    ! grep -q 'dispatch_action\|zz-step' "$DIR/run.sh"
}

@test "package.json bin name is not the bare 'cloudflared'" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.bin['svc-cloudflare'] === 'run.sh' && !('cloudflared' in p.bin) ? 0 : 1)"
    [ "$status" -eq 0 ]
}


@test "opt-in, and mutually exclusive with svc-tailscale on both sides" {
    run node -e "
        const c = require('$DIR/package.json').config, t = require('$REPO_ROOT/svc-tailscale/package.json').config;
        process.exit(c.default === false && c.conflicts.includes('svc-tailscale') && t.conflicts.includes('svc-cloudflare') ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "up refuses on a host where Tailscale is already the internal network" {
    grep -q 'is-active --quiet tailscaled' "$DIR/run.sh"
    grep -q '= "tailscale0"' "$DIR/run.sh"
}

@test "the tunnel token goes in an owner-only env file, never on the unit's command line" {
    grep -q 'umask 077' "$DIR/run.sh"
    grep -q 'EnvironmentFile=' "$DIR/run.sh"
    ! grep -q 'tunnel run --token' "$DIR/run.sh"
    ! grep -q 'service install' "$DIR/run.sh"
}

@test "run.sh persists the internal interface for the other steps, and forgets it on down" {
    grep -q 'vps-network set-internal-interface "\$IFACE"' "$DIR/run.sh"
    grep -q 'vps-network unset-internal-interface "\$IFACE"' "$DIR/run.sh"
}

@test "vps.order puts cloudflare before the firewall step, after nothing it needs" {
    run node -e "const c = require('$DIR/package.json').config.order, s = require('$REPO_ROOT/vps-security/package.json').config.order; process.exit(typeof c === 'number' && c < s ? 0 : 1)"
    [ "$status" -eq 0 ]
}

