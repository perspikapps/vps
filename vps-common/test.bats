#!/usr/bin/env bats
# Moved from ../tests/ to live alongside vps-common/run.sh, matching every
# other folder's <name>/test.bats convention (see README's "Tests" section).
# Covers vps-common/run.sh's pure logic (net_port/all_network_ports/ordered_feature_dirs/
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
    "engines": { "zz-setup": { "ports": [{ "name": "alpha_http", "port": 1111, "access": "public", "note": "n1" }] } }
}
EOF
    cat >"$work/beta/package.json" <<'EOF'
{
    "name": "@tomgrv/beta",
    "engines": { "zz-setup": { "ports": [{ "name": "beta_http", "port": 2222, "access": "private" }] } }
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

@test "net_port: an environment variable named after the port overrides package.json" {
    run bash -c "source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; VPS_SETUP_ROOT='$work'; ALPHA_HTTP_PORT=4242 net_port alpha_http alpha"
    [ "$status" -eq 0 ]
    [ "$output" = "4242" ]
}

@test "all_network_ports: honours the same environment override" {
    run bash -c "source '$REPO_ROOT/vps-common/run.sh'; VPS_SETUP_ROOT='$work'; BETA_HTTP_PORT=4343 all_network_ports"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'beta_http\t4343\tprivate\t'* ]]
    [[ "$output" == *$'alpha_http\t1111\tpublic\tn1'* ]]
}

@test "ordered_feature_dirs: installable steps (with an engines.zz-setup field) in its order, others left out" {
    mkdir -p "$work/gamma" "$work/lib"
    : >"$work/gamma/run.sh"; : >"$work/lib/run.sh"
    echo '{"name":"@tomgrv/gamma","engines":{"zz-setup":{"order":1}}}' >"$work/gamma/package.json"
    echo '{"name":"@tomgrv/lib"}' >"$work/lib/package.json"
    echo '{"name":"@tomgrv/alpha","engines":{"zz-setup":{"order":5}}}' >"$work/alpha/package.json"
    echo '{"name":"@tomgrv/beta","engines":{"zz-setup":{"order":3}}}' >"$work/beta/package.json"
    run bash -c "source '$REPO_ROOT/vps-common/run.sh'; VPS_SETUP_ROOT='$work'; ordered_feature_dirs"
    [ "$status" -eq 0 ]
    [ "$output" = "$work/gamma"$'\n'"$work/beta"$'\n'"$work/alpha" ]
}

@test "dispatch_action: up and down require root, summary does not" {
    run bash -c "
        source '$REPO_ROOT/vps-common/run.sh'
        require_root() { echo needs-root; }
        up() { echo ran-up; }
        down() { echo ran-down; }
        summary() { echo ran-summary; }
        dispatch_action up; dispatch_action down; dispatch_action summary
    "
    [ "$status" -eq 0 ]
    [ "$output" = $'needs-root\nran-up\nneeds-root\nran-down\nran-summary' ]
}

@test "dispatch_action: summary is a silent no-op for a step without one" {
    run bash -c "source '$REPO_ROOT/vps-common/run.sh'; dispatch_action summary"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "download_run: fetches the script to a private temp file, runs it with the shell, removes it" {
    bin=$(mktemp -d)
    printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do [ "$1" = -o ] && { shift; printf "echo ran-installer \\$0\\n" >"$1"; }; shift; done\n' >"$bin/curl"
    chmod +x "$bin/curl"
    run env PATH="$bin:$PATH" bash -c "source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; download_run https://example.test/install.sh bash"
    rm -rf "$bin"
    [ "$status" -eq 0 ]
    [[ "$output" == "ran-installer /tmp/"* ]]
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
{ "name": "some-dep", "engines": { "zz-setup": { "ports": [{ "name": "should_not_appear", "port": 9999, "access": "public" }] } } }
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

@test "dump_diagnostics: shows pods, events, and why an unready pod or a ServiceLB pod is stuck" {
    mkdir -p "$work/bin"
    cat >"$work/bin/kubectl" <<'EOF'
#!/bin/sh
case "$*" in
  *"get pods --no-headers"*"-n kube-system"*|*"-n kube-system get pods --no-headers"*) echo "svclb-rancher-abc 0/2 Pending 0 1m" ;;
  *"-n cattle-system get pods --no-headers"*) echo "rancher-1 0/1 ContainerCreating 0 1m" ;;
  *"describe pod"*) printf 'Name: x\nEvents:\n  Warning  FailedScheduling  node(s) didn'"'"'t have free ports for the requested pod ports\n' ;;
  *"get events"*) echo "5s Warning FailedScheduling pod/svclb-rancher-abc no free ports" ;;
  *) echo "kubectl $*" ;;
esac
EOF
    chmod +x "$work/bin/kubectl"
    run bash -c "export PATH='$work/bin':\$PATH; source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; dump_diagnostics cattle-system"
    [ "$status" -eq 0 ]
    [[ "$output" == *"diagnostics for namespace cattle-system"* ]]
    [[ "$output" == *"FailedScheduling"* ]]
    [[ "$output" == *"free ports"* ]]
    [[ "$output" == *"end of diagnostics"* ]]
}

@test "vps_secret: the environment wins, then the secrets file, then the legacy file" {
    export VPS_SECRETS_FILE="$work/secrets.env"
    printf 'OTHER=x\nDEMO_PW=from-file\n' >"$VPS_SECRETS_FILE"
    printf 'from-legacy\n' >"$work/legacy"
    run bash -c "source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; DEMO_PW=from-env vps_secret DEMO_PW '$work/legacy'"
    [ "$output" = "from-env" ]
    run bash -c "source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; vps_secret DEMO_PW '$work/legacy'"
    [ "$output" = "from-file" ]
    run bash -c "source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; vps_secret NOT_THERE '$work/legacy'"
    [ "$output" = "from-legacy" ]
    run bash -c "source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; vps_secret NOT_THERE"
    [ -z "$output" ]
}

@test "vps_secret_set stores through zz-persist -s and drops the legacy file; vps_secret_unset removes the key" {
    bin=$(mktemp -d)
    printf '#!/bin/sh\n[ "$1" = -s ] && [ "$2" = -f ] && echo "$4=$5" >>"$3"\n' >"$bin/zz-persist"
    chmod +x "$bin/zz-persist"
    export VPS_SECRETS_FILE="$work/secrets.env"
    echo old >"$work/legacy"
    run env PATH="$bin:$PATH" bash -c "source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; vps_secret_set DEMO_PW s3cret '$work/legacy'; vps_secret_set KEEP me"
    [ "$status" -eq 0 ]
    [ ! -e "$work/legacy" ]
    grep -qx 'DEMO_PW=s3cret' "$VPS_SECRETS_FILE"
    run bash -c "source '$REPO_ROOT/vps-common/run.sh' 2>/dev/null; vps_secret_unset DEMO_PW"
    rm -rf "$bin"
    ! grep -q DEMO_PW "$VPS_SECRETS_FILE"
    grep -qx 'KEEP=me' "$VPS_SECRETS_FILE"
}
