#!/usr/bin/env bats

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
SCRIPT="$REPO_ROOT/vps-cert-manager/run.sh"

setup() {
    stubs="$BATS_TEST_TMPDIR/bin"
    calls="$BATS_TEST_TMPDIR/calls"
    mkdir -p "$stubs"
    : >"$calls"
    printf '#!/bin/sh\nexit 0\n' >"$stubs/zz-use"
    # kube-progress just runs the command it wraps
    printf '#!/bin/sh\nshift 2\nexec "$@"\n' >"$stubs/kube-progress"
    printf '#!/bin/sh\necho "helm $*" >>"%s"\n' "$calls" >"$stubs/helm"
    chmod +x "$stubs"/*
}

# stub_kubectl <get deploy exit code>
stub_kubectl() {
    printf '#!/bin/sh\ncase "$1" in get) exit %s ;; esac\ncat >/dev/null 2>&1 </dev/null\n' "$1" >"$stubs/kubectl"
    chmod +x "$stubs/kubectl"
}

@test "run.sh parses as POSIX sh and is a script, not a step" {
    run dash -n "$SCRIPT"
    [ "$status" -eq 0 ]
    run node -e "const p = require('$REPO_ROOT/vps-cert-manager/package.json'); process.exit(p.bin['vps-cert-manager'] === 'run.sh' && !p.engines ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "does nothing when cert-manager is already installed" {
    stub_kubectl 0
    run env PATH="$stubs:$PATH" sh "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed"* ]]
    ! grep -q 'helm upgrade' "$calls"
}

@test "installs the chart with its CRDs and the pinned version" {
    stub_kubectl 1
    run env PATH="$stubs:$PATH" sh "$SCRIPT" -v v1.16.2
    [ "$status" -eq 0 ]
    grep -q '^helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --set crds.enabled=true --version v1.16.2 --wait --timeout 5m$' "$calls"
}
