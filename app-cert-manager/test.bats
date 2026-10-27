#!/usr/bin/env bats

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
SCRIPT="$REPO_ROOT/app-cert-manager/run.sh"

setup() {
    stubs="$BATS_TEST_TMPDIR/bin"
    calls="$BATS_TEST_TMPDIR/calls"
    mkdir -p "$stubs"
    : >"$calls"
    printf '#!/bin/sh\nexit 0\n' >"$stubs/zz-use"
    # the kube/helm helpers (tomgrv/scripts) are stubbed: they record the call
    printf '#!/bin/sh\n' >"$stubs/kube-require"
    for h in helm-repo helm-install; do printf '#!/bin/sh\necho "%s $*" >>"%s"\n' "$h" "$calls" >"$stubs/$h"; done
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
    run node -e "const p = require('$REPO_ROOT/app-cert-manager/package.json'); process.exit(p.bin['app-cert-manager'] === 'run.sh' && !p.engines ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "does nothing when cert-manager is already installed" {
    stub_kubectl 0
    run env PATH="$stubs:$PATH" sh "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed"* ]]
    ! grep -q 'helm-install' "$calls"
}

@test "installs the chart with its CRDs and the pinned version" {
    stub_kubectl 1
    run env PATH="$stubs:$PATH" sh "$SCRIPT" -v v1.16.2
    [ "$status" -eq 0 ]
    grep -qx 'helm-repo jetstack https://charts.jetstack.io' "$calls"
    grep -qx 'helm-install -t 5m cert-manager cert-manager jetstack/cert-manager --set crds.enabled=true --version v1.16.2 --wait' "$calls"
}
