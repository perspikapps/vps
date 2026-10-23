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

@test "run.sh sources the sibling vps-common, else the one zz-use fetches" {
    grep -q 'zz-use "perspikapps/vps/vps-common' "$DIR/run.sh"
    grep -q '^\. "\$common"$' "$DIR/run.sh"
}

@test "run.sh does not bootstrap zz-use itself (assumes setup.sh already ran)" {
    ! grep -q 'command -v zz-use' "$DIR/run.sh"
    ! grep -q 'curl -fsSL.*setup\.sh.*| sh$' "$DIR/run.sh"
}

@test "defines up() and ends with . zz-step" {
    grep -q '^up() {' "$DIR/run.sh"
    grep -q '^\. zz-step$' "$DIR/run.sh"
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

@test "package.json depends on @tomgrv/vps-common" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.dependencies['@tomgrv/vps-common'] === '*' ? 0 : 1)"
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

@test "helm does not --wait for the LoadBalancer Service: the port rebind has to happen first" {
    run awk '/helm upgrade --install rancher/ {h=1} h && /--wait/ {print "found"} /--timeout 10m/ {h=0}' "$DIR/run.sh"
    [ -z "$output" ]
    helm_line=$(grep -n 'helm upgrade --install rancher' "$DIR/run.sh" | head -1 | cut -d: -f1)
    patch_line=$(grep -n 'kube-service-port cattle-system rancher http' "$DIR/run.sh" | head -1 | cut -d: -f1)
    rollout_line=$(grep -n 'rollout status deploy/rancher' "$DIR/run.sh" | head -1 | cut -d: -f1)
    [ "$helm_line" -lt "$patch_line" ]
    [ "$patch_line" -lt "$rollout_line" ]
}

@test "a failed install or rollout dumps diagnostics before exiting" {
    [ "$(grep -c 'kube-diagnose cattle-system' "$DIR/run.sh")" -ge 2 ]
}


@test "an already-rebound Service is removed before helm upgrades, so ports are not merged into duplicates" {
    del_line=$(grep -n 'delete service rancher' "$DIR/run.sh" | head -1 | cut -d: -f1)
    helm_line=$(grep -n 'helm upgrade --install rancher' "$DIR/run.sh" | head -1 | cut -d: -f1)
    patch_line=$(grep -n 'kube-service-port cattle-system rancher http' "$DIR/run.sh" | head -1 | cut -d: -f1)
    [ -n "$del_line" ]
    [ "$del_line" -lt "$helm_line" ]
    [ "$helm_line" -lt "$patch_line" ]
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
    cm_line=$(grep -n '^    kube-cert-manager' "$DIR/run.sh" | head -1 | cut -d: -f1)
    [ "$add_line" -lt "$cm_line" ]
}

@test "Rancher is exposed through a Traefik Ingress on rancher.<wildcard domain>, backed by the http port by name" {
    grep -q 'rancher.\$(wildcard_domain)' "$DIR/run.sh"
    grep -q 'RANCHER_INGRESS:-true' "$DIR/run.sh"
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
