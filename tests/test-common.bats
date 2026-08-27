#!/usr/bin/env bats
# Covers common/run.sh's pure logic (net_port/net_access/all_network_ports/
# feature_package_json/dispatch_action) against a small fixture tree, since
# the rest of common/run.sh (apt helpers, cert-manager, Helm teardown) needs
# a live root/Ubuntu/k3s environment this suite doesn't have.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

setup() {
    work="$BATS_TEST_TMPDIR"
    mkdir -p "$work/alpha" "$work/beta"
    cat >"$work/alpha/package.json" <<'EOF'
{
    "name": "@tomgrv/vps-alpha",
    "vps": { "ports": [{ "name": "alpha_http", "port": 1111, "access": "public", "note": "n1" }] }
}
EOF
    cat >"$work/beta/package.json" <<'EOF'
{
    "name": "@tomgrv/vps-beta",
    "vps": { "ports": [{ "name": "beta_http", "port": 2222, "access": "tailscale" }] }
}
EOF
}

_load_common() {
    # shellcheck disable=SC1091
    source "$REPO_ROOT/common/run.sh"
    VPS_SETUP_ROOT="$work"
}

@test "net_port: resolves another feature's port by name" {
    run bash -c "source '$REPO_ROOT/common/run.sh' 2>/dev/null; VPS_SETUP_ROOT='$work'; net_port alpha_http alpha"
    [ "$status" -eq 0 ]
    [ "$output" = "1111" ]
}

@test "net_access: resolves another feature's access by name" {
    run bash -c "source '$REPO_ROOT/common/run.sh' 2>/dev/null; VPS_SETUP_ROOT='$work'; net_access beta_http beta"
    [ "$status" -eq 0 ]
    [ "$output" = "tailscale" ]
}

@test "all_network_ports: aggregates every feature's ports as TSV" {
    run bash -c "source '$REPO_ROOT/common/run.sh'; VPS_SETUP_ROOT='$work'; all_network_ports"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'alpha_http\t1111\tpublic\tn1'* ]]
    [[ "$output" == *$'beta_http\t2222\ttailscale\t'* ]]
}

@test "feature_package_json: errors on an unknown feature name" {
    run bash -c "source '$REPO_ROOT/common/run.sh'; VPS_SETUP_ROOT='$work'; feature_package_json nonexistent"
    [ "$status" -ne 0 ]
}

@test "dispatch_action: defaults to up(), calls down() when defined" {
    run bash -c "
        source '$REPO_ROOT/common/run.sh'
        up() { echo ran-up; }
        down() { echo ran-down; }
        dispatch_action
        dispatch_action down
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"ran-up"* ]]
    [[ "$output" == *"ran-down"* ]]
}

@test "dispatch_action: errors on an action with no down()" {
    run bash -c "
        source '$REPO_ROOT/common/run.sh'
        up() { echo ran-up; }
        dispatch_action down
    "
    [ "$status" -ne 0 ]
}
