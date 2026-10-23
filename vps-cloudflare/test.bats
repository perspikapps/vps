#!/usr/bin/env bats
# Static checks for vps-cloudflare/run.sh and package.json - a live install
# needs a real root Ubuntu box and a Cloudflare tunnel, so this stops at
# syntax + shape (see ../tests/ for repo-wide checks).

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
DIR="$REPO_ROOT/vps-cloudflare"

@test "run.sh parses as bash" {
    run dash -n "$DIR/run.sh"
    [ "$status" -eq 0 ]
}

@test "run.sh sources the sibling vps-common, else the one zz-use fetches" {
    grep -q 'zz-use "perspikapps/vps/vps-common' "$DIR/run.sh"
    grep -q '^\. "\$common"$' "$DIR/run.sh"
}

@test "defines up(), down() and ends with . zz-step" {
    grep -q '^up() {' "$DIR/run.sh"
    grep -q '^down() {' "$DIR/run.sh"
    grep -q '^\. zz-step$' "$DIR/run.sh"
}

@test "package.json bin name is not the bare 'cloudflared'" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.bin['vps-cloudflare'] === 'run.sh' && !('cloudflared' in p.bin) ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json depends on @tomgrv/vps-common" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.dependencies['@tomgrv/vps-common'] === '*' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "opt-in, and mutually exclusive with vps-tailscale on both sides" {
    run node -e "
        const c = require('$DIR/package.json').config, t = require('$REPO_ROOT/vps-tailscale/package.json').config;
        process.exit(c.default === false && c.conflicts.includes('vps-tailscale') && t.conflicts.includes('vps-cloudflare') ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "up refuses on a host where Tailscale is already the private network" {
    grep -q 'is-active --quiet tailscaled' "$DIR/run.sh"
    grep -q '= "tailscale0"' "$DIR/run.sh"
}

@test "the tunnel token goes in an owner-only env file, never on the unit's command line" {
    grep -q 'umask 077' "$DIR/run.sh"
    grep -q 'EnvironmentFile=' "$DIR/run.sh"
    ! grep -q 'tunnel run --token' "$DIR/run.sh"
    ! grep -q 'service install' "$DIR/run.sh"
}

@test "run.sh persists the private interface for the other steps, and forgets it on down" {
    grep -q 'zz-persist -f "\$VPS_PRIVATE_ACCESS_FILE" VPS_PRIVATE_INTERFACE "\$IFACE"' "$DIR/run.sh"
    grep -q "sed -i \"/\^VPS_PRIVATE_INTERFACE=\${IFACE}" "$DIR/run.sh"
}

@test "vps.order puts cloudflare before the firewall step, after nothing it needs" {
    run node -e "const c = require('$DIR/package.json').config.order, s = require('$REPO_ROOT/vps-security/package.json').config.order; process.exit(typeof c === 'number' && c < s ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "verify refuses to run without a public ip, and warns it must run off-host" {
    grep -q '^verify() {' "$DIR/run.sh"
    grep -q 'run.sh verify <public-ip>' "$DIR/run.sh"
    grep -q 'ANOTHER machine' "$DIR/run.sh"
}
