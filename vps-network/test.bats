#!/usr/bin/env bats
# vps-network: ports, private interface and wildcard state against a fixture
# tree; the address commands need a live host.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
SCRIPT="$REPO_ROOT/vps-network/run.sh"

setup() {
    work="$BATS_TEST_TMPDIR"
    mkdir -p "$work/alpha" "$work/beta" "$work/lib"
    : >"$work/alpha/run.sh"
    : >"$work/beta/run.sh"
    echo '{"workspaces":["alpha","beta","lib"]}' >"$work/package.json"
    echo '{"name":"@x/alpha","bin":{"alpha":"run.sh"},"engines":{"zz-setup":"*"},"config":{"ports":[{"name":"alpha_http","port":1111,"access":"public","note":"n1"}]}}' >"$work/alpha/package.json"
    echo '{"name":"@x/beta","bin":{"beta":"run.sh"},"engines":{"zz-setup":"*"},"config":{"ports":[{"name":"beta_http","port":2222,"access":"private"}]}}' >"$work/beta/package.json"
    # not a step: no engines.zz-setup, so its ports must not count
    echo '{"name":"@x/lib","config":{"ports":[{"name":"lib_http","port":3333,"access":"public"}]}}' >"$work/lib/package.json"
    export VPS_SETUP_ROOT="$work" VPS_PRIVATE_ACCESS_FILE="$work/private.env" VPS_WILDCARD_FILE="$work/wildcard.env"
}

@test "run.sh parses as POSIX sh and is a script, not a step" {
    run dash -n "$SCRIPT"
    [ "$status" -eq 0 ]
    run node -e "const p = require('$REPO_ROOT/vps-network/package.json'); process.exit(p.bin['vps-network'] === 'run.sh' && !p.engines ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "an unknown command is an error" {
    run sh "$SCRIPT" explode
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown command"* ]]
}

@test "port: the declared port, overridden by <NAME>_PORT" {
    run sh "$SCRIPT" port alpha_http
    [ "$output" = "1111" ]
    ALPHA_HTTP_PORT=4242 run sh "$SCRIPT" port alpha_http
    [ "$output" = "4242" ]
}

@test "ports: every step's ports as TSV with the override, steps only" {
    BETA_HTTP_PORT=4343 run sh "$SCRIPT" ports
    [ "$status" -eq 0 ]
    [[ "$output" == *$'alpha_http\t1111\tpublic\tn1'* ]]
    [[ "$output" == *$'beta_http\t4343\tprivate\t'* ]]
    [[ "$output" != *"lib_http"* ]]
}

@test "private interface: the environment wins, then the persisted file, else empty" {
    run sh "$SCRIPT" private-interface
    [ -z "$output" ]
    run sh "$SCRIPT" set-private-interface wg0
    [ "$status" -eq 0 ]
    run sh "$SCRIPT" private-interface
    [ "$output" = "wg0" ]
    VPS_PRIVATE_INTERFACE=eth9 run sh "$SCRIPT" private-interface
    [ "$output" = "eth9" ]
}

@test "unset-private-interface forgets the interface only when it is still the given one" {
    sh "$SCRIPT" set-private-interface wg0 >/dev/null 2>&1
    run sh "$SCRIPT" unset-private-interface tailscale0
    run sh "$SCRIPT" private-interface
    [ "$output" = "wg0" ]
    run sh "$SCRIPT" unset-private-interface wg0
    run sh "$SCRIPT" private-interface
    [ -z "$output" ]
}

@test "private-address is empty without an interface, or when it has no address; summary-host falls back" {
    run sh "$SCRIPT" private-address
    [ -z "$output" ]
    VPS_PRIVATE_INTERFACE=nonexistent9 run sh "$SCRIPT" private-address
    [ -z "$output" ]
    run sh "$SCRIPT" summary-host
    [ "$output" = "<private-ip>" ]
}

@test "wildcard-domain: the environment wins, then the persisted file" {
    WILDCARD_DOMAIN=apps.example.com run sh "$SCRIPT" wildcard-domain
    [ "$output" = "apps.example.com" ]
    sh "$SCRIPT" set-wildcard-domain saved.example.com >/dev/null 2>&1
    run sh "$SCRIPT" wildcard-domain
    [ "$output" = "saved.example.com" ]
}

@test "wildcard-domain: the nip.io fallback uses the public address, never the private interface" {
    mkdir -p "$work/bin"
    printf '#!/bin/sh\necho 203.0.113.9\n' >"$work/bin/curl"
    printf '#!/bin/sh\necho "1.1.1.1 via 10.0.0.1 dev eth0 src 10.0.0.5"\n' >"$work/bin/ip"
    chmod +x "$work/bin/curl" "$work/bin/ip"
    # NAT'd default-route address -> asks the echo service; a private interface is set but ignored
    PATH="$work/bin:$PATH" VPS_PRIVATE_INTERFACE=tailscale0 run sh "$SCRIPT" wildcard-domain
    [ "$output" = "203-0-113-9.nip.io" ]
    printf '#!/bin/sh\necho "1.1.1.1 via 54.37.230.1 dev eth0 src 54.37.230.112"\n' >"$work/bin/ip"
    PATH="$work/bin:$PATH" run sh "$SCRIPT" wildcard-domain
    [ "$output" = "54-37-230-112.nip.io" ]
}
