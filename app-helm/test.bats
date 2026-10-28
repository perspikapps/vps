#!/usr/bin/env bats
# app-helm against stubbed kube/helm tools and a stubbed vps-network.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
SCRIPT="$REPO_ROOT/app-helm/run.sh"

setup() {
    stubs="$BATS_TEST_TMPDIR/bin"
    calls="$BATS_TEST_TMPDIR/calls"
    root="$BATS_TEST_TMPDIR/root"
    mkdir -p "$stubs" "$root/charts/demo"
    : >"$calls"
    echo 'apiVersion: v2' >"$root/charts/demo/Chart.yaml"
    printf '#!/bin/sh\nexit 0\n' >"$stubs/zz-use"
    : >"$stubs/zz-colors"
    printf '#!/bin/sh\nshift; echo "$*" >&2\n' >"$stubs/zz-log"
    printf '#!/bin/sh\n' >"$stubs/kube-require"
    printf '#!/bin/sh\necho "helm $*" >>"%s"\n' "$calls" >"$stubs/helm"
    printf '#!/bin/sh\necho "kubectl $*" >>"%s"\n' "$calls" >"$stubs/kubectl"
    # helm-install records its arguments and the values file it was given
    printf '#!/bin/sh\necho "helm-install $*" >>"%s"\nwhile [ "$#" -gt 0 ]; do [ "$1" = --values ] && cat "$2" >>"%s"; shift; done\n' "$calls" "$calls" >"$stubs/helm-install"
    printf '#!/bin/sh\necho "kube-teardown $*" >>"%s"\n' "$calls" >"$stubs/kube-teardown"
    chmod +x "$stubs"/*
}

# stub_route <access> <domain> <middlewares> [certresolver]
stub_route() {
    printf '#!/bin/sh\ncase "$1" in\naccess-route) printf "route_access=%s\\nroute_domain=%s\\nroute_middlewares=%s\\nroute_certresolver=%s\\n" "%s" "%s" "%s" "%s" ;;\nsummary-block) shift; echo "block $*" ;;\nvisibility) echo %s ;;\nesac\n' "'$1'" "'$2'" "'$3'" "'$4'" "$1" "$2" "$3" "$4" "$1" >"$stubs/vps-network"
    chmod +x "$stubs/vps-network"
}

run_app() {
    run env PATH="$stubs:$PATH" ZZ_SETUP_ROOT="$root" sh "$SCRIPT" "$@"
}

@test "run.sh parses as POSIX sh and is a script, not a step" {
    run dash -n "$SCRIPT"
    [ "$status" -eq 0 ]
    run node -e "const p = require('$REPO_ROOT/app-helm/package.json'); process.exit(p.bin['app-helm'] === 'run.sh' && !p.engines ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "up installs the chart with the shared domain and the helm arguments, no middlewares for a public route" {
    stub_route public apps.example.com ""
    run_app up demo --middlewares-key ingress.middlewares --set a=b
    [ "$status" -eq 0 ]
    grep -q '^helm dependency update .*charts/demo' "$calls"
    grep -q '^helm-install demo demo .*charts/demo --values .* --set a=b$' "$calls"
    grep -q '"domain": "apps.example.com"' "$calls"
    ! grep -q 'middlewares' "$calls"
}

@test "up sets the chart's middlewares value for an internal route" {
    stub_route internal in.example.com kube-system-internal-only@kubernetescrd
    run_app up demo --middlewares-key dashboard.ingress.middlewares
    [ "$status" -eq 0 ]
    grep -q '"middlewares": "kube-system-internal-only@kubernetescrd"' "$calls"
}

@test "up sets the chart's certresolver value for a public route with a resolver" {
    stub_route public apps.example.com "" letsencrypt
    run_app up demo --middlewares-key dashboard.ingress.middlewares
    [ "$status" -eq 0 ]
    grep -q '"certresolver": "letsencrypt"' "$calls"
}

@test "up fails without a chart, and down tears the release and namespace down" {
    stub_route public apps.example.com ""
    run_app up missing
    [ "$status" -ne 0 ]
    run_app down demo
    [ "$status" -eq 0 ]
    grep -qx 'kube-teardown demo demo' "$calls"
}
