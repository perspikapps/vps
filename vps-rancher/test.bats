#!/usr/bin/env bats
# Static checks for vps-rancher/run.sh and package.json - a live install
# needs a real root Ubuntu box, so this stops at syntax + shape (see
# this folder's README's "Tests" section, and ../tests/ for repo-wide checks).

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
DIR="$REPO_ROOT/vps-rancher"

@test "run.sh parses as POSIX sh (dash)" {
    run dash -n "$DIR/run.sh"
    [ "$status" -eq 0 ]
}

@test "run.sh sources nothing but zz-colors and calls the vps scripts instead" {
    grep -q '^\. zz-colors$' "$DIR/run.sh"
    [ -z "$(grep -E '^\s*(\.|source) ' "$DIR/run.sh" | grep -v '\. zz-colors')" ]
}

@test "run.sh does not bootstrap zz-use itself (assumes setup.sh already ran)" {
    ! grep -q 'command -v zz-use' "$DIR/run.sh"
    ! grep -q 'curl -fsSL.*setup\.sh.*| sh$' "$DIR/run.sh"
}

@test "defines up() and dispatches its action" {
    grep -q '^up() {' "$DIR/run.sh"
    grep -q '^case "\${1:-}" in' "$DIR/run.sh"
    ! grep -q 'dispatch_action\|zz-step' "$DIR/run.sh"
}

@test "defines down()" {
    grep -q '^down() {' "$DIR/run.sh"
}

@test "package.json bin entry matches the folder name" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.bin['vps-rancher'] === 'run.sh' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json declares vps.order as a number" {
    run node -e "const p = require('$DIR/package.json'); process.exit(typeof p.config.order === 'number' ? 0 : 1)"
    [ "$status" -eq 0 ]
}


@test "package.json depends on @tomgrv/vps-k3s" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.dependencies['@tomgrv/vps-k3s'] === '*' ? 0 : 1)"
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

@test "the long waits report progress (helm install and rollout status are wrapped)" {
    grep -q 'kube-progress cattle-system "Rancher install"' "$DIR/run.sh"
    grep -q 'kube-progress cattle-system "Rancher rollout"' "$DIR/run.sh"
}

@test "a failed install or rollout dumps diagnostics before exiting" {
    [ "$(grep -c 'kube-diagnose cattle-system' "$DIR/run.sh")" -ge 2 ]
}


@test "the chart repository comes from RANCHER_CHART_REPO_URL (community latest by default), not a hard-coded alias" {
    grep -q 'RANCHER_CHART_REPO_URL:-https://releases.rancher.com/server-charts/latest' "$DIR/run.sh"
    grep -q 'helm repo add vps-rancher "\$RANCHER_CHART_REPO_URL" --force-update' "$DIR/run.sh"
    grep -q 'helm upgrade --install rancher vps-rancher/rancher' "$DIR/run.sh"
    ! grep -q 'rancher-latest' "$DIR/run.sh"
}

@test "RANCHER_CHART_REPO_URL is a declared, optional input defaulting to the community repository" {
    run node -e "const i = require('$DIR/package.json').config.inputs.RANCHER_CHART_REPO_URL; process.exit(i && i.required === false && i.default === 'https://releases.rancher.com/server-charts/latest' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "a repository URL that is not http(s) is rejected before anything is installed" {
    grep -q 'http://\* | https://\*)' "$DIR/run.sh"
    grep -q 'must be an http(s) Helm repository URL' "$DIR/run.sh"
    [ "$(grep -n 'must be an http(s)' "$DIR/run.sh" | cut -d: -f1)" -lt "$(grep -n 'helm repo add' "$DIR/run.sh" | head -1 | cut -d: -f1)" ]
}

@test "the bitnami Helm repository is added as part of the install, before cert-manager" {
    grep -q 'helm repo add bitnami https://charts.bitnami.com/bitnami' "$DIR/run.sh"
    add_line=$(grep -n 'helm repo add bitnami' "$DIR/run.sh" | head -1 | cut -d: -f1)
    cm_line=$(grep -n '^    "\$vps_cert_manager"' "$DIR/run.sh" | head -1 | cut -d: -f1)
    [ "$add_line" -lt "$cm_line" ]
}

@test "Rancher is exposed through a Traefik Ingress on rancher.<wildcard domain>, backed by the http port by name" {
    grep -q 'rancher.\$(vps-network access-domain' "$DIR/run.sh"
    grep -q 'ingressClassName: traefik' "$DIR/helm/ingress.yaml"
    grep -q 'name: http$' "$DIR/helm/ingress.yaml"
    run node -e "const i = require('$DIR/package.json').config.inputs.RANCHER_INGRESS_HOST; process.exit(i && i.required === false ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "chart values and the Traefik Ingress live in yaml files beside run.sh, not in heredocs or --set" {
    [ -f "$DIR/helm/values.yaml" ]
    [ -f "$DIR/helm/ingress.yaml" ]
    grep -q -- '--values "\${dir}/helm/values.yaml"' "$DIR/run.sh"
    grep -q 'yaml-render "\${dir}/helm/ingress.yaml" INGRESS_HOST=' "$DIR/run.sh"
    ! grep -q -- '--set ' "$DIR/run.sh"
    ! grep -q '^kind: Ingress' "$DIR/run.sh"
}

@test "Rancher's route is public or internal, never both: RANCHER_ACCESS picks the entrypoint" {
    grep -q 'visibility rancher' "$DIR/run.sh"
    grep -q 'internal) entrypoints="internal,internalsecure"' "$DIR/run.sh"
    grep -q 'router.entrypoints: ${ENTRYPOINTS}' "$DIR/helm/ingress.yaml"
    run node -e "const i = require('$DIR/package.json').config.inputs.RANCHER_ACCESS; process.exit(i && i.required === false && require('$DIR/package.json').config.visibility === 'public' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "Rancher has no port of its own: a ClusterIP Service reached only through Traefik" {
    grep -q 'type: ClusterIP' "$DIR/helm/values.yaml"
    ! grep -q 'kube-service-port' "$DIR/run.sh"
    run node -e "const p = require('$DIR/package.json'); process.exit(p.config.ports || p.config.inputs.RANCHER_INGRESS ? 1 : 0)"
    [ "$status" -eq 0 ]
}
