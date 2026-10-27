#!/usr/bin/env bats
# vps-network: ports, internal interface and wildcard state against a fixture
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
    export VPS_SETUP_ROOT="$work" SYSTEM_NETWORK_FILE="$work/network.env"
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

@test "internal interface: the environment wins, then the persisted file, else empty" {
    run sh "$SCRIPT" internal-interface
    [ -z "$output" ]
    run sh "$SCRIPT" set-internal-interface wg0
    [ "$status" -eq 0 ]
    run sh "$SCRIPT" internal-interface
    [ "$output" = "wg0" ]
    SYSTEM_INTERNAL_INTERFACE=eth9 run sh "$SCRIPT" internal-interface
    [ "$output" = "eth9" ]
}

@test "unset-internal-interface forgets the interface only when it is still the given one" {
    sh "$SCRIPT" set-internal-interface wg0 >/dev/null 2>&1
    run sh "$SCRIPT" unset-internal-interface tailscale0
    run sh "$SCRIPT" internal-interface
    [ "$output" = "wg0" ]
    run sh "$SCRIPT" unset-internal-interface wg0
    run sh "$SCRIPT" internal-interface
    [ -z "$output" ]
}

@test "internal-address is empty without an interface, or when it has no address; summary-host falls back" {
    run sh "$SCRIPT" internal-address
    [ -z "$output" ]
    SYSTEM_INTERNAL_INTERFACE=nonexistent9 run sh "$SCRIPT" internal-address
    [ -z "$output" ]
    run sh "$SCRIPT" summary-host
    [ "$output" = "<internal-ip>" ]
}

@test "external-domain: the environment wins, then the persisted file" {
    SYSTEM_EXTERNAL_DOMAIN=apps.example.com run sh "$SCRIPT" external-domain
    [ "$output" = "apps.example.com" ]
    sh "$SCRIPT" set-external-domain saved.example.com >/dev/null 2>&1
    run sh "$SCRIPT" external-domain
    [ "$output" = "saved.example.com" ]
}

@test "internal-domain: defaults to the external domain" {
    SYSTEM_EXTERNAL_DOMAIN=apps.example.com run sh "$SCRIPT" internal-domain
    [ "$output" = "apps.example.com" ]
}

@test "external-domain: the nip.io fallback uses the instance (default route) address, never the internal interface" {
    mkdir -p "$work/bin"
    printf '#!/bin/sh\necho "1.1.1.1 via 54.37.230.1 dev eth0 src 54.37.230.112"\n' >"$work/bin/ip"
    chmod +x "$work/bin/ip"
    PATH="$work/bin:$PATH" SYSTEM_INTERNAL_INTERFACE=tailscale0 run sh "$SCRIPT" external-domain
    [ "$output" = "54-37-230-112.nip.io" ]
}

@test "visibility: the system lists, then the saved choice, then config.visibility, else public; no per-app variable" {
    run sh "$SCRIPT" visibility alpha
    [ "$output" = "public" ]
    echo '{"name":"@x/alpha","bin":{"alpha":"run.sh"},"engines":{"zz-setup":"*"},"config":{"visibility":"internal"}}' >"$work/alpha/package.json"
    run sh "$SCRIPT" visibility alpha
    [ "$output" = "internal" ]
    sh "$SCRIPT" set-visibility alpha public
    run sh "$SCRIPT" visibility alpha
    [ "$output" = "public" ]
    SYSTEM_INTERNAL_APPS=beta,alpha run sh "$SCRIPT" visibility alpha
    [ "$output" = "internal" ]
    SYSTEM_PUBLIC_APPS=alpha run sh "$SCRIPT" visibility alpha
    [ "$output" = "public" ]
    ALPHA_ACCESS=internal run sh "$SCRIPT" visibility alpha
    [ "$output" = "public" ]
}

@test "set-visibility rejects anything but public or internal" {
    run sh "$SCRIPT" set-visibility alpha sideways
    [ "$status" -ne 0 ]
}

@test "internal-domain: SYSTEM_INTERNAL_DOMAIN, else the saved one" {
    SYSTEM_INTERNAL_DOMAIN=in.example.com run sh "$SCRIPT" internal-domain
    [ "$output" = "in.example.com" ]
    sh "$SCRIPT" set-internal-domain saved.example.com
    run sh "$SCRIPT" internal-domain
    [ "$output" = "saved.example.com" ]
}

@test "visibilities: the service names, without the vps- prefix or ./, with their visibility" {
    mkdir -p "$work/vps-gamma"
    : >"$work/vps-gamma/run.sh"
    echo '{"workspaces":["alpha","beta","lib","vps-gamma"]}' >"$work/package.json"
    echo '{"name":"@x/vps-gamma","bin":{"vps-gamma":"run.sh"},"engines":{"zz-setup":"*"},"config":{"visibility":"internal"}}' >"$work/vps-gamma/package.json"
    run sh "$SCRIPT" visibilities
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'gamma\tinternal')" ]
}

@test "visibilities: under zz-setup, only the services this run brings up (ZZ_SETUP_UP)" {
    mkdir -p "$work/vps-gamma"
    : >"$work/vps-gamma/run.sh"
    echo '{"workspaces":["alpha","beta","lib","vps-gamma"]}' >"$work/package.json"
    echo '{"name":"@x/vps-gamma","bin":{"vps-gamma":"run.sh"},"engines":{"zz-setup":"*"},"config":{"visibility":"internal"}}' >"$work/vps-gamma/package.json"
    ZZ_SETUP_UP=" alpha beta " run sh "$SCRIPT" visibilities
    [ -z "$output" ]
    ZZ_SETUP_UP=" alpha vps-gamma " run sh "$SCRIPT" visibilities
    [ "$output" = "$(printf 'gamma\tinternal')" ]
}

@test "access-route: the route of a service for eval, public with Let's Encrypt, internal behind the internal-only middleware" {
    SYSTEM_EXTERNAL_DOMAIN=apps.example.com run sh "$SCRIPT" access-route alpha
    [ "$status" -eq 0 ]
    [[ "$output" == *"route_access='public'"* ]]
    [[ "$output" == *"route_domain='apps.example.com'"* ]]
    [[ "$output" == *"route_middlewares=''"* ]]
    [[ "$output" == *"route_certresolver='letsencrypt'"* ]]
    SYSTEM_INTERNAL_APPS=alpha SYSTEM_INTERNAL_DOMAIN=in.example.com run sh "$SCRIPT" access-route alpha
    [[ "$output" == *"route_access='internal'"* ]]
    [[ "$output" == *"route_domain='in.example.com'"* ]]
    [[ "$output" == *"route_middlewares='kube-system-internal-only@kubernetescrd'"* ]]
    [[ "$output" == *"route_certresolver=''"* ]]
}

@test "access-route makes the caller exit 1 on a missing domain, and ignores a per-app ACCESS variable" {
    ALPHA_ACCESS=sideways run sh "$SCRIPT" access-route alpha
    [[ "$output" == *"route_access='public'"* ]]
    SYSTEM_INTERNAL_APPS=alpha run sh "$SCRIPT" access-route alpha
    [[ "$output" == *"exit 1" ]]
}

@test "internal-range: what the provider declared with the interface, forgotten with it; no environment variable" {
    sh "$SCRIPT" set-internal-interface wg0 10.9.0.0/24 >/dev/null 2>&1
    run sh "$SCRIPT" internal-range
    [ "$output" = "10.9.0.0/24" ]
    SYSTEM_INTERNAL_SOURCE_RANGE=1.2.3.0/24 K3S_INTERNAL_SOURCE_RANGE=1.2.3.0/24 run sh "$SCRIPT" internal-range
    [ "$output" = "10.9.0.0/24" ]
    sh "$SCRIPT" unset-internal-interface wg0 >/dev/null 2>&1
    run sh "$SCRIPT" internal-range
    [ -z "$output" ]
}

@test "internal-range: the internal address and loopback when the provider declared none" {
    mkdir -p "$work/bin"
    printf '#!/bin/sh\necho "3: tailscale0    inet 100.64.0.5/32 scope global tailscale0"\n' >"$work/bin/ip"
    chmod +x "$work/bin/ip"
    sh "$SCRIPT" set-internal-interface tailscale0 >/dev/null 2>&1
    PATH="$work/bin:$PATH" run sh "$SCRIPT" internal-range
    [ "$output" = "100.64.0.5/32,127.0.0.1/32" ]
}

@test "public-ip: the source address of the default route" {
    mkdir -p "$work/bin"
    printf '#!/bin/sh\necho "1.1.1.1 via 10.0.0.1 dev eth0 src 10.0.0.5"\n' >"$work/bin/ip"
    chmod +x "$work/bin/ip"
    PATH="$work/bin:$PATH" run sh "$SCRIPT" public-ip
    [ "$output" = "10.0.0.5" ]
}

@test "everything persisted lands in the one network file; unset-access drops only the access choices" {
    sh "$SCRIPT" set-internal-interface wg0 >/dev/null 2>&1
    sh "$SCRIPT" set-external-domain apps.example.com
    sh "$SCRIPT" set-internal-domain in.example.com
    sh "$SCRIPT" set-visibility alpha internal
    grep -q '^SYSTEM_INTERNAL_INTERFACE=wg0$' "$work/network.env"
    grep -q '^SYSTEM_EXTERNAL_DOMAIN=apps.example.com$' "$work/network.env"
    grep -q '^SYSTEM_ACCESS_ALPHA=internal$' "$work/network.env"
    sh "$SCRIPT" unset-access
    ! grep -q 'SYSTEM_ACCESS_ALPHA\|SYSTEM_INTERNAL_DOMAIN' "$work/network.env"
    grep -q '^SYSTEM_INTERNAL_INTERFACE=wg0$' "$work/network.env"
    grep -q '^SYSTEM_EXTERNAL_DOMAIN=apps.example.com$' "$work/network.env"
}
