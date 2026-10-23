#!/usr/bin/env bats
# Moved from ../tests/ to live alongside vps-common/run.sh, matching every
# other folder's <name>/test.bats convention (see README's "Tests" section).
# Covers vps-common/run.sh's pure logic (net_port/all_network_ports/feature_dirs/
# dispatch_action) against a small fixture tree, since
# the rest of vps-common/run.sh (apt helpers, cert-manager, Helm teardown) needs
# a live root/Ubuntu/k3s environment this suite doesn't have.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

setup() {
    work="$BATS_TEST_TMPDIR"
    mkdir -p "$work/alpha" "$work/beta"
    # feature_dirs/all_network_ports only look at directories with a
    # run.sh alongside package.json (skips node_modules/*) - fixtures need
    # one too, even though nothing here executes it.
    : >"$work/alpha/run.sh"
    : >"$work/beta/run.sh"
    # zz-workspaces reads the root package.json's "workspaces"
    echo '{"workspaces":["alpha","beta","gamma","lib"]}' >"$work/package.json"
    # zz-workspaces lists a folder only when its bin file exists and engines.zz-setup is set
    cat >"$work/alpha/package.json" <<'EOF'
{
    "name": "@tomgrv/alpha",
    "bin": { "alpha": "run.sh" }, "engines": { "zz-setup": "*" }, "config": { "ports": [{ "name": "alpha_http", "port": 1111, "access": "public", "note": "n1" }] }
}
EOF
    cat >"$work/beta/package.json" <<'EOF'
{
    "name": "@tomgrv/beta",
    "bin": { "beta": "run.sh" }, "engines": { "zz-setup": "*" }, "config": { "ports": [{ "name": "beta_http", "port": 2222, "access": "private" }] }
}
EOF
}

_load_common() {
    # shellcheck disable=SC1091
    source "$REPO_ROOT/vps-common/run.sh"
    VPS_SETUP_ROOT="$work"
}

@test "net_port: resolves a port by name from the calling step's package.json" {
    run bash -c "cd '$work/alpha'; source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; net_port alpha_http"
    [ "$status" -eq 0 ]
    [ "$output" = "1111" ]
}

@test "net_port: an environment variable named after the port overrides package.json" {
    run bash -c "cd '$work/alpha'; source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; ALPHA_HTTP_PORT=4242 net_port alpha_http"
    [ "$status" -eq 0 ]
    [ "$output" = "4242" ]
}

@test "all_network_ports: honours the same environment override" {
    run bash -c "source '$REPO_ROOT/vps-common/run.sh'; VPS_SETUP_ROOT='$work'; BETA_HTTP_PORT=4343 all_network_ports"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'beta_http\t4343\tprivate\t'* ]]
    [[ "$output" == *$'alpha_http\t1111\tpublic\tn1'* ]]
}

@test "feature_dirs: installable steps (with an engines.zz-setup field) in its order, others left out" {
    mkdir -p "$work/gamma" "$work/lib"
    : >"$work/gamma/run.sh"; : >"$work/lib/run.sh"
    echo '{"name":"@tomgrv/gamma","bin":{"gamma":"run.sh"},"engines":{"zz-setup":"*"},"config": {"order":1}}' >"$work/gamma/package.json"
    echo '{"name":"@tomgrv/lib"}' >"$work/lib/package.json"
    echo '{"name":"@tomgrv/alpha","bin":{"alpha":"run.sh"},"engines":{"zz-setup":"*"},"config": {"order":5}}' >"$work/alpha/package.json"
    echo '{"name":"@tomgrv/beta","bin":{"beta":"run.sh"},"engines":{"zz-setup":"*"},"config": {"order":3}}' >"$work/beta/package.json"
    run bash -c "source '$REPO_ROOT/vps-common/run.sh'; VPS_SETUP_ROOT='$work'; feature_dirs"
    [ "$status" -eq 0 ]
    [ "$output" = "$work/gamma"$'\n'"$work/beta"$'\n'"$work/alpha" ]
}




@test "all_network_ports: aggregates every feature's ports as TSV" {
    run bash -c "source '$REPO_ROOT/vps-common/run.sh'; VPS_SETUP_ROOT='$work'; all_network_ports"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'alpha_http\t1111\tpublic\tn1'* ]]
    [[ "$output" == *$'beta_http\t2222\tprivate\t'* ]]
}

@test "all_network_ports: skips node_modules/* (no run.sh alongside its package.json)" {
    mkdir -p "$work/node_modules/some-dep"
    cat >"$work/node_modules/some-dep/package.json" <<'EOF'
{ "name": "some-dep", "engines": { "zz-setup": "*" }, "config": { "ports": [{ "name": "should_not_appear", "port": 9999, "access": "public" }] } }
EOF
    run bash -c "source '$REPO_ROOT/vps-common/run.sh'; VPS_SETUP_ROOT='$work'; all_network_ports"
    [ "$status" -eq 0 ]
    [[ "$output" != *"should_not_appear"* ]]
}




@test "run.sh parses as bash" {
    run bash -n "$REPO_ROOT/vps-common/run.sh"
    [ "$status" -eq 0 ]
}

@test "package.json bin entry matches the folder name" {
    run node -e "const p = require('$REPO_ROOT/vps-common/package.json'); process.exit(p.bin['vps-common'] === 'run.sh' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "private_interface: the environment wins, then the persisted file, else empty" {
    run bash -c "source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; VPS_PRIVATE_ACCESS_FILE='$work/pa.env'; private_interface"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    printf 'OTHER=x\nVPS_PRIVATE_INTERFACE=tailscale0\n' >"$work/pa.env"
    run bash -c "source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; VPS_PRIVATE_ACCESS_FILE='$work/pa.env'; private_interface"
    [ "$output" = "tailscale0" ]
    run bash -c "source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; VPS_PRIVATE_ACCESS_FILE='$work/pa.env'; VPS_PRIVATE_INTERFACE=wg0; private_interface"
    [ "$output" = "wg0" ]
}

@test "private_address: empty without an interface, or when it has no address" {
    run bash -c "source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; VPS_PRIVATE_ACCESS_FILE='$work/none.env'; private_address"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run bash -c "source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; VPS_PRIVATE_INTERFACE=nonexistent9; private_address"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "wildcard_domain: the environment wins, then the persisted file, else nip.io (or empty with no address)" {
    run bash -c "source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; VPS_WILDCARD_FILE='$work/wc.env'; WILDCARD_DOMAIN=apps.example.com wildcard_domain"
    [ "$output" = "apps.example.com" ]
    printf 'WILDCARD_DOMAIN=saved.example.org\n' >"$work/wc.env"
    run bash -c "source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; VPS_WILDCARD_FILE='$work/wc.env'; wildcard_domain"
    [ "$output" = "saved.example.org" ]
    run bash -c "source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; VPS_WILDCARD_FILE='$work/none.env'; wildcard_domain"
    [ "$status" -eq 0 ]
    [[ -z "$output" || "$output" =~ ^[0-9]+-[0-9]+-[0-9]+-[0-9]+\.nip\.io$ ]]
}

@test "wildcard_domain: the nip.io fallback uses the public address, never the private interface" {
    mkdir -p "$work/bin"
    printf '#!/bin/sh\necho 203.0.113.9\n' >"$work/bin/curl"
    printf '#!/bin/sh\necho "1.1.1.1 via 10.0.0.1 dev eth0 src 10.0.0.5"\n' >"$work/bin/ip"
    chmod +x "$work/bin/curl" "$work/bin/ip"
    # NAT'd default-route address -> asks the echo service; private interface set but ignored
    run bash -c "export PATH='$work/bin':\$PATH; source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; VPS_WILDCARD_FILE='$work/none.env'; VPS_PRIVATE_INTERFACE=tailscale0; wildcard_domain"
    [ "$output" = "203-0-113-9.nip.io" ]
    printf '#!/bin/sh\necho "1.1.1.1 via 54.37.230.1 dev eth0 src 54.37.230.112"\n' >"$work/bin/ip"
    run bash -c "export PATH='$work/bin':\$PATH; source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; VPS_WILDCARD_FILE='$work/none.env'; wildcard_domain"
    [ "$output" = "54-37-230-112.nip.io" ]
}

# kubectl stub printing a pod list: one ready, one still pulling its image.





