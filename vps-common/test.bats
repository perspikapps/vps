#!/usr/bin/env bats
# Moved from ../tests/ to live alongside vps-common/run.sh, matching every
# other folder's <name>/test.bats convention (see README's "Tests" section).
# Covers vps-common/run.sh's pure logic (net_port/net_access/all_network_ports/
# feature_package_json/dispatch_action) against a small fixture tree, since
# the rest of vps-common/run.sh (apt helpers, cert-manager, Helm teardown) needs
# a live root/Ubuntu/k3s environment this suite doesn't have.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

setup() {
    work="$BATS_TEST_TMPDIR"
    mkdir -p "$work/alpha" "$work/beta"
    # feature_package_json/all_network_ports only look at directories with a
    # run.sh alongside package.json (skips node_modules/*) - fixtures need
    # one too, even though nothing here executes it.
    : >"$work/alpha/run.sh"
    : >"$work/beta/run.sh"
    cat >"$work/alpha/package.json" <<'EOF'
{
    "name": "@tomgrv/alpha",
    "vps": { "ports": [{ "name": "alpha_http", "port": 1111, "access": "public", "note": "n1" }] }
}
EOF
    cat >"$work/beta/package.json" <<'EOF'
{
    "name": "@tomgrv/beta",
    "vps": { "ports": [{ "name": "beta_http", "port": 2222, "access": "tailscale" }] }
}
EOF
}

_load_common() {
    # shellcheck disable=SC1091
    source "$REPO_ROOT/vps-common/run.sh"
    VPS_SETUP_ROOT="$work"
}

@test "net_port: resolves another feature's port by name" {
    run bash -c "source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; VPS_SETUP_ROOT='$work'; net_port alpha_http alpha"
    [ "$status" -eq 0 ]
    [ "$output" = "1111" ]
}

@test "net_access: resolves another feature's access by name" {
    run bash -c "source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; VPS_SETUP_ROOT='$work'; net_access beta_http beta"
    [ "$status" -eq 0 ]
    [ "$output" = "tailscale" ]
}

@test "all_network_ports: aggregates every feature's ports as TSV" {
    run bash -c "source '$REPO_ROOT/vps-common/run.sh'; VPS_SETUP_ROOT='$work'; all_network_ports"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'alpha_http\t1111\tpublic\tn1'* ]]
    [[ "$output" == *$'beta_http\t2222\ttailscale\t'* ]]
}

@test "all_network_ports: skips node_modules/* (no run.sh alongside its package.json)" {
    mkdir -p "$work/node_modules/some-dep"
    cat >"$work/node_modules/some-dep/package.json" <<'EOF'
{ "name": "some-dep", "vps": { "ports": [{ "name": "should_not_appear", "port": 9999, "access": "public" }] } }
EOF
    run bash -c "source '$REPO_ROOT/vps-common/run.sh'; VPS_SETUP_ROOT='$work'; all_network_ports"
    [ "$status" -eq 0 ]
    [[ "$output" != *"should_not_appear"* ]]
}

@test "feature_package_json: errors on an unknown feature name" {
    run bash -c "source '$REPO_ROOT/vps-common/run.sh'; VPS_SETUP_ROOT='$work'; feature_package_json nonexistent"
    [ "$status" -ne 0 ]
}

@test "dispatch_action: defaults to up(), calls down() when defined" {
    run bash -c "
        source '$REPO_ROOT/vps-common/run.sh'
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
        source '$REPO_ROOT/vps-common/run.sh'
        up() { echo ran-up; }
        dispatch_action down
    "
    [ "$status" -ne 0 ]
}

@test "run.sh parses as bash" {
    run bash -n "$REPO_ROOT/vps-common/run.sh"
    [ "$status" -eq 0 ]
}

@test "package.json bin entry matches the folder name" {
    run node -e "const p = require('$REPO_ROOT/vps-common/package.json'); process.exit(p.bin['vps-common'] === 'run.sh' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

# kubectl stub printing a pod list: one ready, one still pulling its image.
_stub_kubectl() {
    mkdir -p "$work/bin"
    cat >"$work/bin/kubectl" <<'EOF'
#!/bin/sh
printf 'rancher-1 1/1 Running 0 1m\nrancher-2 0/1 ContainerCreating 0 1m\n'
EOF
    chmod +x "$work/bin/kubectl"
}

@test "run_with_progress: logs elapsed time and pod states while the command runs, keeps its output" {
    _stub_kubectl
    run bash -c "export PATH='$work/bin':\$PATH; source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; PROGRESS_INTERVAL=1; run_with_progress cattle-system 'Rancher install' bash -c 'sleep 3; echo done-output'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rancher install: 1s, 1/2 pods ready - waiting: rancher-2=ContainerCreating"* ]]
    [[ "$output" == *"done-output"* ]]
}

@test "run_with_progress: returns the command's exit status and stops reporting afterwards" {
    _stub_kubectl
    run bash -c "export PATH='$work/bin':\$PATH; source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; PROGRESS_INTERVAL=1; rc=0; run_with_progress ns label bash -c 'sleep 2; exit 7' || rc=\$?; sleep 2; echo rc=\$rc"
    [[ "$output" == *"rc=7"* ]]
    # one line per elapsed second only while the command ran (not after it exited)
    [ "$(printf '%s\n' "$output" | grep -c 'label: ')" -le 2 ]
}

@test "progress_line: says so when the namespace has no pod yet" {
    mkdir -p "$work/bin"
    printf '#!/bin/sh\nexit 0\n' >"$work/bin/kubectl"
    chmod +x "$work/bin/kubectl"
    run bash -c "export PATH='$work/bin':\$PATH; source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; progress_line cattle-system 'Rancher install' 15"
    [[ "$output" == *"no pod in cattle-system yet"* ]]
}
