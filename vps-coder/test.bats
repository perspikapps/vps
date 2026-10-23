#!/usr/bin/env bats
# Static checks for vps-coder/run.sh and package.json - the install needs a
# live k3s cluster, so this stops at syntax + shape.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
DIR="$REPO_ROOT/vps-coder"

@test "run.sh parses as POSIX sh" {
    run dash -n "$DIR/run.sh"
    [ "$status" -eq 0 ]
}

@test "run.sh sources nothing but zz-colors and calls the vps scripts instead" {
    grep -q '^\. zz-colors$' "$DIR/run.sh"
    [ -z "$(grep -E '^\s*(\.|source) ' "$DIR/run.sh" | grep -v '\. zz-colors')" ]
}

@test "defines up(), down() and is a config.functions step" {
    grep -q '^up() {' "$DIR/run.sh"
    grep -q '^down() {' "$DIR/run.sh"
    run node -e "const p = require('$DIR/package.json'); process.exit(p.config.functions === true ? 0 : 1)"
    [ "$status" -eq 0 ]
    ! grep -q 'dispatch_action\|zz-step' "$DIR/run.sh"
}

@test "follows the Coder Rancher guide: bitnami postgres, coder-db-url secret, upstream chart" {
    grep -q 'bitnami/postgresql' "$DIR/run.sh"
    grep -q 'coder-db-url' "$DIR/run.sh"
    grep -q 'https://helm.coder.com/v2' "$DIR/run.sh"
    grep -q 'CODER_PG_CONNECTION_URL' "$DIR/helm/coder-values.yaml"
}

@test "the database password is generated and stored, never a fixed value or a --set argument" {
    grep -q 'zz-persist -f "\$VPS_SECRETS_FILE" -s -g 24 CODER_DB_PASSWORD' "$DIR/run.sh"
    ! grep -q 'random_password' "$DIR/run.sh"
    ! grep -q 'auth.password=' "$DIR/run.sh"
}

@test "opt-in, depends on vps-rancher, ordered after it" {
    run node -e "
        const p = require('$DIR/package.json'), r = require('$REPO_ROOT/vps-rancher/package.json');
        process.exit(p.config.default === false && p.dependencies['@tomgrv/vps-rancher'] === '*' && p.config.order > r.config.order ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "exposed through the Traefik ingress, access URL and wildcard from the same domain (cookie scope)" {
    grep -q 'className: traefik' "$DIR/helm/coder-values.yaml"
    grep -q 'wildcardHost' "$DIR/helm/coder-values-wildcard.yaml"
    grep -q 'http://coder.${wildcard}' "$DIR/run.sh"
    grep -q '\*\.${wildcard}' "$DIR/run.sh"
    ! grep -q 'kube-service-port' "$DIR/run.sh"
}


@test "creates the first admin and the devcontainer template, best effort, with the password stored" {
    grep -q '/users/first' "$DIR/run.sh"
    grep -q 'kubernetes-devcontainer' "$DIR/run.sh"
    grep -q 'zz-persist -f "\$VPS_SECRETS_FILE" -s -g 24 CODER_ADMIN_PASSWORD' "$DIR/run.sh"
    grep -q 'bootstrap_coder' "$DIR/run.sh"
    grep -q 'finish it in the UI' "$DIR/run.sh"
}

@test "the admin password and session token never appear on a command line" {
    ! grep -q -- '--first-user-password' "$DIR/run.sh"
    ! grep -qE 'CODER_SESSION_TOKEN=\$' "$DIR/run.sh"
    grep -q "d @-" "$DIR/run.sh" || grep -q -- '-d @-' "$DIR/run.sh"
}

@test "charts come first: the platform is installed before the admin/template step, which only warns" {
    inst=$(grep -n '^    install_devcontainer_builder ||' "$DIR/run.sh" | head -1 | cut -d: -f1)
    boot=$(grep -n '^    bootstrap_coder "\$admin_email"' "$DIR/run.sh" | head -1 | cut -d: -f1)
    [ -n "$inst" ]
    [ -n "$boot" ]
    [ "$inst" -lt "$boot" ]
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
    grep -q 'image: registry:2' "$DIR/helm/registry.yaml"
    grep -q 'insecureRegistries' "$DIR/helm/devcontainer-builder-values.yaml"
    grep -q '/etc/rancher/k3s/registries.yaml' "$DIR/run.sh"
    run node -e "const p = require('$DIR/package.json').config.ports.find(x => x.name === 'devcontainer_registry'); process.exit(p && p.port === 5000 && p.access === 'private' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "the registry token never appears on a command line (values file, stdin)" {
    ! grep -q -- '--set .*password' "$DIR/run.sh"
    grep -q 'registryAuth' "$DIR/helm/devcontainer-builder-values.yaml"
}


@test "BuildKit is deployed by the step (chart 0.5.0's bundled one is broken): privileged, endpoint passed to the chart, plain-HTTP registry in buildkitd.toml" {
    grep -q '^deploy_buildkit() {' "$DIR/run.sh"
    grep -q 'moby/buildkit' "$DIR/helm/buildkit.yaml"
    grep -q 'http = true' "$DIR/run.sh"
    grep -q 'endpoint: tcp://buildkit' "$DIR/helm/devcontainer-builder-values.yaml"
    ! grep -q 'deploy: {enabled: true}' "$DIR/run.sh"
}

@test "a failed devcontainer-builder release from an earlier attempt is forgotten by record, never uninstalled (it may own the namespace)" {
    grep -q 'delete secret -l owner=helm,name=devcontainer-builder' "$DIR/run.sh"
    ! grep -q 'helm uninstall devcontainer-builder' "$DIR/run.sh"
}

@test "one workspace namespace everywhere: RBAC for coder:coder, pull secret and both templates use it" {
    grep -q 'WORKSPACE_NAMESPACE="\${CODER_WORKSPACE_NAMESPACE:-coder-workspaces}"' "$DIR/run.sh"
    grep -q '^ensure_workspace_namespace() {' "$DIR/run.sh"
    grep -q 'kind: Role' "$DIR/helm/workspace-rbac.yaml"
    grep -q 'namespace: \${coder_namespace}' "$DIR/helm/workspace-rbac.yaml"
    grep -q 'kubectl -n "\$WORKSPACE_NAMESPACE" create secret docker-registry devcontainer-images' "$DIR/run.sh"
    ! grep -q -- '--var namespace=\${CODER_NAMESPACE}' "$DIR/run.sh"
    ! grep -q "namespace='\"\$CODER_NAMESPACE\"'" "$DIR/run.sh"
    run node -e "const i = require('$DIR/package.json').config.inputs.CODER_WORKSPACE_NAMESPACE; process.exit(i && i.default === 'coder-workspaces' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "every helm/*.yaml renders to valid YAML with its placeholders filled" {
    python3 -c 'import yaml' 2>/dev/null || skip "python3 yaml not installed"
    command -v yaml-render >/dev/null || skip "yaml-render not installed"
    for f in "$DIR"/helm/*.yaml; do
        names=$(grep -o '\${[a-z_]*}' "$f" | tr -d '${}' | sort -u | tr '\n' ' ')
        args=""
        for n in $names; do
            case "$n" in
                registry_auth | insecure_registries) args="$args $n=[]" ;;
                wildcard_host) args="$args $n=*.example.com" ;;
                *) args="$args $n=example" ;;
            esac
        done
        # shellcheck disable=SC2086
        out=$(set -f; yaml-render "$f" $args)
        [ -z "$(printf '%s' "$out" | grep '\${')" ]
        printf '%s' "$out" | python3 -c 'import sys, yaml; list(yaml.safe_load_all(sys.stdin))'
    done
}
