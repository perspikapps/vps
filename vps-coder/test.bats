#!/usr/bin/env bats
# Static checks for vps-coder/run.sh and package.json - the install needs a
# live k3s cluster, so this stops at syntax + shape.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
DIR="$REPO_ROOT/vps-coder"

@test "run.sh parses as bash" {
    run bash -n "$DIR/run.sh"
    [ "$status" -eq 0 ]
}

@test "run.sh bootstraps zz-use and sources common" {
    grep -q 'zz-use "perspikapps/vps/vps-common' "$DIR/run.sh"
    grep -q '^\. vps-common$' "$DIR/run.sh"
}

@test "defines up(), down() and dispatches via dispatch_action" {
    grep -q '^up() {' "$DIR/run.sh"
    grep -q '^down() {' "$DIR/run.sh"
    grep -q 'dispatch_action "\$@"' "$DIR/run.sh"
}

@test "follows the Coder Rancher guide: bitnami postgres, coder-db-url secret, upstream chart" {
    grep -q 'bitnami/postgresql' "$DIR/run.sh"
    grep -q 'coder-db-url' "$DIR/run.sh"
    grep -q 'https://helm.coder.com/v2' "$DIR/run.sh"
    grep -q 'CODER_PG_CONNECTION_URL' "$DIR/run.sh"
}

@test "the database password is generated and stored, never a fixed value or a --set argument" {
    grep -q 'random_password' "$DIR/run.sh"
    grep -q 'vps_secret_set CODER_DB_PASSWORD' "$DIR/run.sh"
    ! grep -q 'auth.password=' "$DIR/run.sh"
}

@test "opt-in, depends on vps-rancher, ordered after it" {
    run node -e "
        const p = require('$DIR/package.json'), r = require('$REPO_ROOT/vps-rancher/package.json');
        process.exit(p.config.default === false && p.dependencies['@tomgrv/vps-rancher'] === '*' && p.config.order > r.config.order ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "exposed through the Traefik ingress, access URL and wildcard from the same domain (cookie scope)" {
    grep -q 'className: "traefik"' "$DIR/run.sh"
    grep -q 'wildcardHost' "$DIR/run.sh"
    grep -q 'http://coder.${WILDCARD}' "$DIR/run.sh"
    grep -q '\*\.${WILDCARD}' "$DIR/run.sh"
    ! grep -q 'patch_service_port' "$DIR/run.sh"
}

@test "fails early, naming ZZ_SETUP_REF, when the cached vps-common predates wildcard_domain" {
    grep -q 'declare -F wildcard_domain' "$DIR/run.sh"
    grep -q 'ZZ_SETUP_REF=<ref> zz-setup' "$DIR/run.sh"
}

@test "creates the first admin and the devcontainer template, best effort, with the password stored" {
    grep -q '/users/first' "$DIR/run.sh"
    grep -q 'kubernetes-devcontainer' "$DIR/run.sh"
    grep -q 'vps_secret_set CODER_ADMIN_PASSWORD' "$DIR/run.sh"
    grep -q 'bootstrap_coder' "$DIR/run.sh"
    grep -q 'finish it in the UI' "$DIR/run.sh"
}

@test "the admin password and session token never appear on a command line" {
    ! grep -q -- '--first-user-password' "$DIR/run.sh"
    ! grep -qE 'CODER_SESSION_TOKEN=\$' "$DIR/run.sh"
    grep -q "d @-" "$DIR/run.sh" || grep -q -- '-d @-' "$DIR/run.sh"
}

@test "charts come first: the platform is installed before the admin/template step, which only warns" {
    inst=$(grep -n '^install_devcontainer_builder ||' "$DIR/run.sh" | head -1 | cut -d: -f1)
    boot=$(grep -n '^bootstrap_coder "\$ADMIN_EMAIL"' "$DIR/run.sh" | head -1 | cut -d: -f1)
    [ -n "$inst" ] && [ -n "$boot" ] && [ "$inst" -lt "$boot" ]
    grep -q 'incomplete (see above)' "$DIR/run.sh"
}

@test "devcontainer-builder is third-party: latest chart is resolved and logged, the template ref must be pinned, never a default branch" {
    grep -q 'helm show chart' "$DIR/run.sh"
    grep -q 'Pin it with DEVCONTAINER_BUILDER_VERSION' "$DIR/run.sh"
    grep -q 'fetch -q --depth 1 .* "\$DEVCONTAINER_BUILDER_REF"' "$DIR/run.sh"
    ! grep -q 'git clone' "$DIR/run.sh"
    run node -e "const i = require('$DIR/package.json').config.inputs; process.exit(i.DEVCONTAINER_REGISTRY_TOKEN.secret === true ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "in-cluster registry: anonymous registry:2 on a private port, with the builder told it is plain HTTP and containerd given a mirror" {
    grep -q 'image: registry:2' "$DIR/run.sh"
    grep -q 'insecureRegistries' "$DIR/run.sh"
    grep -q '/etc/rancher/k3s/registries.yaml' "$DIR/run.sh"
    run node -e "const p = require('$DIR/package.json').config.ports.find(x => x.name === 'devcontainer_registry'); process.exit(p && p.port === 5000 && p.access === 'private' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "the registry token never appears on a command line (values file, stdin)" {
    ! grep -q -- '--set .*password' "$DIR/run.sh"
    grep -q 'registryAuth' "$DIR/run.sh"
}

@test "a bootstrap action retries only the admin/template step, and each failure names its step" {
    grep -q '"bootstrap"' "$DIR/run.sh"
    grep -q 'POST /users/first' "$DIR/run.sh"
    grep -q 'template failed (see above)' "$DIR/run.sh"
}

@test "BuildKit is deployed by the step (chart 0.5.0's bundled one is broken): privileged, endpoint passed to the chart, plain-HTTP registry in buildkitd.toml" {
    grep -q '^deploy_buildkit() {' "$DIR/run.sh"
    grep -q 'moby/buildkit' "$DIR/run.sh"
    grep -q 'http = true' "$DIR/run.sh"
    grep -q 'buildkit: {endpoint:' "$DIR/run.sh"
    ! grep -q 'deploy: {enabled: true}' "$DIR/run.sh"
}

@test "a failed devcontainer-builder release from an earlier attempt is forgotten by record, never uninstalled (it may own the namespace)" {
    grep -q 'delete secret -l owner=helm,name=devcontainer-builder' "$DIR/run.sh"
    ! grep -q 'helm uninstall devcontainer-builder' "$DIR/run.sh"
}
