#!/usr/bin/env bats
# Static checks for app-rancher/run.sh and package.json - a live install
# needs a real root Ubuntu box, so this stops at syntax + shape (see
# this folder's README's "Tests" section, and ../tests/ for repo-wide checks).

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
DIR="$REPO_ROOT/app-rancher"

@test "run.sh parses as POSIX sh (dash)" {
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
    run node -e "const p = require('$DIR/package.json'); process.exit(p.bin['app-rancher'] === 'run.sh' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json declares vps.order as a number" {
    run node -e "const p = require('$DIR/package.json'); process.exit(typeof p.config.order === 'number' ? 0 : 1)"
    [ "$status" -eq 0 ]
}


@test "package.json depends on @tomgrv/svc-k3s" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.dependencies['@tomgrv/svc-k3s'] === '*' ? 0 : 1)"
    [ "$status" -eq 0 ]
}


@test "hostname and bootstrapPassword are passed as strings via a values file, not --set" {
    ! grep -q -- '--set bootstrapPassword' "$DIR/run.sh"
    ! grep -q -- '--set hostname' "$DIR/run.sh"
    grep -q -- '--values "\$values_file"' "$DIR/run.sh"
}

@test "a numeric-looking bootstrap password stays a string in the values file" {
    command -v jq >/dev/null || skip "jq not installed"
    out=$(jq -n --arg hostname "1.2.3.4" --arg bootstrapPassword "12345678" \
        '{hostname: $hostname, bootstrapPassword: $bootstrapPassword}')
    [ "$(printf '%s' "$out" | jq -r '.bootstrapPassword | type')" = "string" ]
    [ "$(printf '%s' "$out" | jq -r '.bootstrapPassword')" = "12345678" ]
}

@test "RANCHER_CHART_REPO_URL is a declared, optional input defaulting to the community repository" {
    run node -e "const i = require('$DIR/package.json').config.inputs.RANCHER_CHART_REPO_URL; process.exit(i && i.required === false && i.default === 'https://releases.rancher.com/server-charts/latest' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "chart values and the Traefik Ingress live in yaml files beside run.sh, not in heredocs or --set" {
    [ -f "$DIR/helm/values.yaml" ]
    [ -f "$DIR/helm/ingress.yaml" ]
    grep -q -- '--values "\${dir}/helm/values.yaml"' "$DIR/run.sh"
    grep -q 'kube-apply "\${dir}/helm/ingress.yaml" INGRESS_HOST=' "$DIR/run.sh"
    ! grep -q -- '--set ' "$DIR/run.sh"
    ! grep -q '^kind: Ingress' "$DIR/run.sh"
}

@test "Rancher has no port of its own: a ClusterIP Service reached only through Traefik" {
    grep -q 'type: ClusterIP' "$DIR/helm/values.yaml"
    ! grep -q 'kube-service-port' "$DIR/run.sh"
    run node -e "const p = require('$DIR/package.json'); process.exit(p.config.ports || p.config.inputs.RANCHER_INGRESS ? 1 : 0)"
    [ "$status" -eq 0 ]
}

@test "Rancher has an https route and an http route that only redirects, both ahead of any catch-all" {
    grep -q 'name: rancher-traefik-http' "$DIR/helm/ingress.yaml"
    grep -q 'router.entrypoints: websecure' "$DIR/helm/ingress.yaml"
    [ "$(grep -c "router.priority: '1000'" "$DIR/helm/ingress.yaml")" -eq 2 ]
    grep -q 'kube-system-redirect-https@kubernetescrd' "$DIR/run.sh"
}

@test "install, repositories and the rollout wait go through the shared kube/helm helpers" {
    grep -q 'helm-install cattle-system rancher app-rancher/rancher' "$DIR/run.sh"
    grep -q 'kube-rollout -t 10m cattle-system rancher' "$DIR/run.sh"
    grep -q 'eval "\$(kube-require)"' "$DIR/run.sh"
    ! grep -Eq '^\s+(kube-progress|kube-diagnose) |helm upgrade|helm repo' "$DIR/run.sh"
}

@test "the chart repository comes from RANCHER_CHART_REPO_URL (community latest by default), with bitnami, before cert-manager" {
    grep -q 'RANCHER_CHART_REPO_URL:-https://releases.rancher.com/server-charts/latest' "$DIR/run.sh"
    grep -q 'helm-repo app-rancher "\$RANCHER_CHART_REPO_URL" bitnami https://charts.bitnami.com/bitnami' "$DIR/run.sh"
    ! grep -q 'rancher-latest' "$DIR/run.sh"
    repo_line=$(grep -n '^    helm-repo' "$DIR/run.sh" | head -1 | cut -d: -f1)
    cm_line=$(grep -n '^    "\$app_cert_manager"' "$DIR/run.sh" | head -1 | cut -d: -f1)
    [ "$repo_line" -lt "$cm_line" ]
}

@test "Rancher's host, hostname and public/internal choice come from the system config, not from step inputs" {
    grep -q 'vps-network access-route rancher' "$DIR/run.sh"
    grep -q 'ingress_host="rancher.\${route_domain}"' "$DIR/run.sh"
    grep -q 'middlewares="\$route_middlewares"' "$DIR/run.sh"
    ! grep -q 'kube-system-internal-only\|RANCHER_ACCESS\|RANCHER_INGRESS_HOST\|RANCHER_HOSTNAME' "$DIR/run.sh"
    run node -e "const i = require('$DIR/package.json').config.inputs; process.exit(['RANCHER_ACCESS', 'RANCHER_INGRESS_HOST', 'RANCHER_HOSTNAME'].some(k => k in i) ? 1 : 0)"
    [ "$status" -eq 0 ]
}

@test "Rancher is exposed through a Traefik Ingress, backed by the http port by name" {
    grep -q 'ingressClassName: traefik' "$DIR/helm/ingress.yaml"
    grep -q 'name: http$' "$DIR/helm/ingress.yaml"
}
