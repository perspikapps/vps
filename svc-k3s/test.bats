#!/usr/bin/env bats
# Static checks for svc-k3s/run.sh and package.json - a live install
# needs a real root Ubuntu box, so this stops at syntax + shape (see
# this folder's README's "Tests" section, and ../tests/ for repo-wide checks).

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
DIR="$REPO_ROOT/svc-k3s"

@test "run.sh parses as POSIX sh" {
    run dash -n "$DIR/run.sh"
    [ "$status" -eq 0 ]
}

@test "run.sh sources nothing but zz-colors and calls the vps scripts instead" {
    grep -q '^\. zz-colors$' "$DIR/run.sh"
    [ -z "$(grep -E '^\s*(\.|source) ' "$DIR/run.sh" | grep -Ev '\. zz-(colors|step)$')" ]
}

@test "run.sh does not bootstrap zz-use itself (assumes setup.sh already ran)" {
    ! grep -q 'command -v zz-use' "$DIR/run.sh"
    ! grep -q 'curl -fsSL.*setup\.sh.*| sh$' "$DIR/run.sh"
}

@test "defines up() and dispatches its action" {
    grep -q '^up() {' "$DIR/run.sh"
    grep -q '^\. zz-step$' "$DIR/run.sh"
    ! grep -q 'dispatch_action' "$DIR/run.sh"
}

@test "defines down()" {
    grep -q '^down() {' "$DIR/run.sh"
}

@test "package.json bin entry matches the folder name" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.bin['svc-k3s'] === 'run.sh' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json declares vps.order as a number" {
    run node -e "const p = require('$DIR/package.json'); process.exit(typeof p.config.order === 'number' ? 0 : 1)"
    [ "$status" -eq 0 ]
}




@test "summary shows the public IP for the public Traefik ports, not the first local address" {
    sed -n '/^summary() {/,/^}/p' "$DIR/run.sh" | grep -q 'public-ip'
    ! sed -n '/^summary() {/,/^}/p' "$DIR/run.sh" | grep -q 'hostname -I'
}

@test "Traefik's chart values live in traefik-config.yaml, rendered by run.sh" {
    [ -f "$DIR/helm/traefik-config.yaml" ]
    grep -q 'kind: HelmChartConfig' "$DIR/helm/traefik-config.yaml"
    grep -q 'kube-apply "\$(dirname "\$0")/helm/traefik-config.yaml"' "$DIR/run.sh"
    ! grep -q 'kind: HelmChartConfig' "$DIR/run.sh"
}

@test "internal routes share 80/443: a shared internal-only ipAllowList middleware, and the client address is kept" {
    [ -f "$DIR/helm/internal-middleware.yaml" ]
    grep -q 'ipAllowList' "$DIR/helm/internal-middleware.yaml"
    grep -q 'externalTrafficPolicy: Local' "$DIR/helm/traefik-config.yaml"
    grep -q 'allowCrossNamespace=true' "$DIR/helm/traefik-config.yaml"
    ! grep -q 'internalsecure' "$DIR/helm/traefik-config.yaml"
    grep -q 'redirectScheme' "$DIR/helm/redirect-middleware.yaml"
    grep -q 'kube-apply "\$(dirname "\$0")/helm/internal-middleware.yaml"' "$DIR/run.sh"
}