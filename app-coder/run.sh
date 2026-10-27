#!/bin/sh
# Coder on the cluster, following https://coder.com/docs/install/server/rancher
# (namespace, Bitnami PostgreSQL, db-url Secret, upstream chart) but with the
# helm CLI instead of the Rancher UI. Env vars: see README.

set -eu
zz-use zz-colors zz-log zz-persist yaml-render kube-require kube-rollout kube-teardown helm-repo helm-install kube-apply
# shellcheck disable=SC1091
. zz-colors

CODER_NAMESPACE=coder
# Where workspaces run: one namespace for the template's `namespace` variable, the pull secret and
# the RBAC (the Coder chart's own permissions cover only its release namespace). The platform page's name.
WORKSPACE_NAMESPACE="${CODER_WORKSPACE_NAMESPACE:-coder-workspaces}"
printf '%s\n' "$WORKSPACE_NAMESPACE" | grep -Eq '^[a-z0-9]([-a-z0-9]*[a-z0-9])?$' ||
    { zz-log e "CODER_WORKSPACE_NAMESPACE must be a lowercase RFC 1123 label (got '${WORKSPACE_NAMESPACE}')." && exit 1; }
REGISTRY_PORT="$(vps-network port coder_registry)"
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
CODER_API=http://127.0.0.1:18080/api/v2
# Chart values and manifests, rendered with yaml-render (see helm/).
HELM_DIR="$(cd "$(dirname "$0")" && pwd)/helm"

# The workspace namespace, with rights for Coder's service account (coder:coder) to run workspaces in it:
# the template creates a Deployment and a PVC (and the builder template reads pods/events).
ensure_workspace_namespace() {
    local coder_namespace="$CODER_NAMESPACE"

    [ "$WORKSPACE_NAMESPACE" != "$CODER_NAMESPACE" ] || return 0
    zz-log i "Preparing the workspace namespace '${WORKSPACE_NAMESPACE}' (Coder's service account may manage workspaces there)..."
    kubectl create namespace "$WORKSPACE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    kube-apply -n "$WORKSPACE_NAMESPACE" "$HELM_DIR/workspace-rbac.yaml" coder_namespace="$coder_namespace"
}

# Creates the first admin (once) and the "devcontainer" template (once), through
# a port-forward to the pod: Traefik and DNS are not needed, and the template
# comes from the starter embedded in the server's own `coder` binary, so it
# always matches the installed version. Everything here is best effort: a
# failure warns and leaves a working Coder (create them in the UI instead).
bootstrap_coder() {
    local email="$1" user="$2" pw="$3" i pf_pid

    kubectl -n "$CODER_NAMESPACE" port-forward deploy/coder 18080:8080 >/dev/null 2>&1 &
    pf_pid=$!
    for i in $(seq 1 30); do
        curl -fs -o /dev/null "$CODER_API/buildinfo" && break
        sleep 2
    done
    run_bootstrap_steps "$email" "$user" "$pw" || zz-log w "Coder admin/template bootstrap incomplete (see above); finish it in the UI."
    kill "$pf_pid" 2>/dev/null || true
}

run_bootstrap_steps() {
    local email="$1" user="$2" pw="$3" code token

    curl -fs -o /dev/null "$CODER_API/buildinfo" || { zz-log w "Coder API not reachable through the port-forward." && return 1; }

    code="$(curl -s -o /dev/null -w '%{http_code}' "$CODER_API/users/first")"
    if [ "$code" = "404" ]; then
        zz-log i "Creating the Coder admin user '${user}'..."
        jq -n --arg e "$email" --arg u "$user" --arg p "$pw" '{email: $e, username: $u, name: $u, password: $p, trial: false}' |
            curl -fsS -o /dev/null -X POST -H 'Content-Type: application/json' -d @- "$CODER_API/users/first" ||
            { zz-log w "Creating the first Coder user failed (POST /users/first)." && return 1; }
    fi

    token="$(jq -n --arg e "$email" --arg p "$pw" '{email: $e, password: $p}' |
        curl -fsS -X POST -H 'Content-Type: application/json' -d @- "$CODER_API/users/login" 2>/dev/null | jq -r '.session_token // empty')" || true
    [ -n "$token" ] || { zz-log w "Could not log in as '${email}' (password changed since?); skipping the template." && return 1; }

    # the platform (devcontainer-builder + registry) is installed before the admin step;
    # its template is pushed only when it is up and the template repo ref is pinned
    if [ "${BUILDER_READY:-}" = "1" ]; then
        if printf '%s\n' "${CODER_DEVCONTAINER_BUILDER_REF:-}" | grep -Eq '^[0-9A-Za-z][0-9A-Za-z._/-]*$'; then
            push_coder_template "$token" kubernetes-devcontainer || { zz-log w "Pushing the kubernetes-devcontainer template failed (see above)." && return 1; }
            return 0
        fi
        zz-log w "devcontainer-builder is installed, but its template is third-party code and must be pinned: set CODER_DEVCONTAINER_BUILDER_REF (a tag or commit of github.com/DeepSpaceCartel/devcontainer-builder). Using the Envbuilder starter instead."
    fi
    push_coder_template "$token" envbuilder || { zz-log w "Pushing the Envbuilder 'devcontainer' template failed (see above)." && return 1; }
    zz-log i "Template pushed."
}

# In-cluster registry for the built images (anonymous, plain HTTP, no TLS): registry:2 with a PVC, on
# hostPort 5000 so that both BuildKit (pods) and containerd (kubelet, which cannot resolve cluster DNS)
# reach it as <node ip>:5000 (helm/registry.yaml). Port 5000 is declared "private" in package.json, so
# ufw and the FORWARD guard keep it off the internet. containerd needs a registries.yaml mirror to pull
# over HTTP.
deploy_local_registry() {
    local addr="$1" cfg=/etc/rancher/k3s/registries.yaml registry_port="$REGISTRY_PORT" i

    zz-log i "Deploying the in-cluster image registry at ${addr}..."
    kubectl create namespace devcontainer-builder --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace devcontainer-builder pod-security.kubernetes.io/enforce=privileged --overwrite
    kube-apply -n devcontainer-builder "$HELM_DIR/registry.yaml" registry_port="$registry_port"
    kube-rollout devcontainer-builder registry
    vps-network reapply-guard
    if [ ! -f "$cfg" ]; then
        zz-log i "Letting containerd pull ${addr} over HTTP (${cfg}); restarting k3s (running pods keep running)..."
        printf 'mirrors:\n  "%s":\n    endpoint:\n      - "http://%s"\n' "$addr" "$addr" >"$cfg"
        systemctl restart k3s
        for i in $(seq 1 60); do
            kubectl get --raw /readyz >/dev/null 2>&1 && break
            sleep 2
        done
    elif ! grep -qF "$addr" "$cfg"; then
        zz-log w "${cfg} exists without ${addr}: add a mirror with endpoint http://${addr} yourself, then restart k3s, or workspaces cannot pull the built images."
    fi
}

# BuildKit for devcontainer-builder (helm/buildkit.yaml), deployed here instead of through the chart's
# bundled option: chart 0.5.0's bundled sub-chart names its container after the Helm alias
# ("buildkitBundled", not a valid name), and it cannot be told about a plain-HTTP registry from here.
# $1: a plain-HTTP registry host:port, or "".
deploy_buildkit() {
    local plain_http="$1" toml="" config_sha

    [ -z "$plain_http" ] || toml="$(printf '[registry."%s"]\n  http = true\n  insecure = true\n' "$plain_http")"
    config_sha="$(printf '%s' "$toml" | sha256sum | cut -c1-16)"
    kubectl -n devcontainer-builder create configmap buildkitd-config --from-literal=buildkitd.toml="$toml" \
        --dry-run=client -o yaml | kubectl apply -f -
    kube-apply -n devcontainer-builder "$HELM_DIR/buildkit.yaml" config_sha="$config_sha"
    kube-rollout devcontainer-builder buildkit
}

# devcontainer-builder (https://deepspacecartel.github.io/devcontainer-builder/getting-started/platform/):
# builds a repo's devcontainer.json into an image pushed to a registry, with its own BuildKit (needs a
# privileged namespace). Third-party chart: an unset CODER_DEVCONTAINER_BUILDER_VERSION resolves to the latest
# and is logged so it can be pinned. The registry is the external one when DEVCONTAINER_REGISTRY_* are
# set, else the in-cluster one. Sets BUILDER_READY=1 for the template step.
install_devcontainer_builder() {
    local values chart=oci://ghcr.io/deepspacecartel/charts/devcontainer-builder version="${CODER_DEVCONTAINER_BUILDER_VERSION:-}"
    local registry mapped auth_user auth_pw node_ip insecure_registries='[]' insecure_host="" registry_auth status

    if [ -z "$version" ]; then
        version="$(helm show chart "$chart" 2>/dev/null | awk '/^version:/ {print $2; exit}')" || true
        [ -n "$version" ] || { zz-log w "Could not resolve the latest devcontainer-builder chart version." && return 1; }
        zz-log w "CODER_DEVCONTAINER_BUILDER_VERSION not set: installing the latest chart, ${version}. Pin it with CODER_DEVCONTAINER_BUILDER_VERSION=${version}."
    fi
    if [ -n "${CODER_DEVCONTAINER_REGISTRY_TOKEN:-}" ] && [ -n "${CODER_DEVCONTAINER_REGISTRY_USER:-}" ] && [ -n "${CODER_DEVCONTAINER_REGISTRY_ORG:-}" ]; then
        registry="${CODER_DEVCONTAINER_REGISTRY:-ghcr.io}"
        mapped="${registry}/${CODER_DEVCONTAINER_REGISTRY_ORG}"
        auth_user="$CODER_DEVCONTAINER_REGISTRY_USER"
        auth_pw="$CODER_DEVCONTAINER_REGISTRY_TOKEN"
    else
        node_ip="$(hostname -I | awk '{print $1}')"
        registry="${node_ip}:${REGISTRY_PORT}"
        mapped="${registry}/devcontainers"
        auth_user=""
        auth_pw=""
        deploy_local_registry "$registry" || return 1
        insecure_registries="$(jq -nc --arg r "$registry" '[$r]')"
        insecure_host="$registry"
    fi
    zz-log i "Installing devcontainer-builder chart ${version} (images go to ${mapped})..."
    kubectl create namespace devcontainer-builder --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace devcontainer-builder pod-security.kubernetes.io/enforce=privileged --overwrite
    deploy_buildkit "${insecure_host}" || return 1
    registry_auth="$(jq -nc --arg reg "$registry" --arg user "$auth_user" --arg tok "$auth_pw" \
        'if $user == "" then [] else [{registry: $reg, username: $user, password: $tok}] end')"
    values="$(mktemp)"
    yaml-render "$HELM_DIR/devcontainer-builder-values.yaml" mapped="$mapped" registry_auth="$registry_auth" insecure_registries="$insecure_registries" >"$values"
    helm-install devcontainer-builder devcontainer-builder "$chart" \
        --version "$version" --values "$values" --wait || { rm -f "$values" && return 1; }
    rm -f "$values"
    # workspaces pull the built images with this secret (a dummy login when the registry is anonymous)
    kubectl -n "$WORKSPACE_NAMESPACE" create secret docker-registry devcontainer-images \
        --docker-server="$registry" --docker-username="${auth_user:-anonymous}" --docker-password="${auth_pw:-anonymous}" \
        --dry-run=client -o yaml | kubectl apply -f -
    BUILDER_READY=1
    DEVCONTAINER_IMAGE_REGISTRY="$mapped"
}

# Coder's "Kubernetes (Devcontainer)" starter is pushed as the "devcontainer" template, then
# patched (helm/devcontainer-vscode.tf, the icons below) and named TEMPLATE_REV: bump it when
# the patch changes, so an existing template gets a new version.
TEMPLATE_REV=vps-r2

# push_coder_template TOKEN KIND: pushes once (an existing template is left as is), from inside
# the Coder pod (its `coder` CLI matches the server). Token goes in on stdin, not argv.
push_coder_template() {
    local token="$1" kind="$2" name vars src tpl ver cur rev

    if [ "$kind" = "kubernetes-devcontainer" ]; then name=kubernetes-devcontainer; else name=devcontainer; fi
    tpl="$(curl -fsS -H "Coder-Session-Token: $token" "$CODER_API/templates" | jq -c --arg n "$name" '.[] | select(.name == $n)')" || tpl=""
    if [ -n "$tpl" ]; then
        ver="$(printf '%s' "$tpl" | jq -r '.active_version_id')"
        cur="$(curl -fsS -H "Coder-Session-Token: $token" "$CODER_API/templateversions/${ver}/variables" 2>/dev/null | jq -r '.[] | select(.name == "namespace") | .value // empty')" || cur=""
        rev="$(curl -fsS -H "Coder-Session-Token: $token" "$CODER_API/templateversions/${ver}" 2>/dev/null | jq -r '.name // empty')" || rev=""
        # only the patched starter carries a revision; the third-party template is left alone
        [ "$kind" = "kubernetes-devcontainer" ] && rev="$TEMPLATE_REV"
        if [ "$cur" = "$WORKSPACE_NAMESPACE" ] && [ "$rev" = "$TEMPLATE_REV" ]; then
            zz-log i "Template '${name}' already exists (namespace ${cur}, ${rev}); leaving it as is."
            return 0
        fi
        zz-log i "Template '${name}' is namespace '${cur:-unknown}', revision '${rev:-unknown}' (wanted '${WORKSPACE_NAMESPACE}', ${TEMPLATE_REV}): pushing a new version."
    fi
    zz-log i "Creating the '${name}' template..."
    if [ "$kind" = "kubernetes-devcontainer" ]; then
        # the template repo at the pinned tag/commit, not its default branch
        src="$(mktemp -d)"
        { git -C "$src" init -q && git -C "$src" fetch -q --depth 1 https://github.com/DeepSpaceCartel/devcontainer-builder.git "$CODER_DEVCONTAINER_BUILDER_REF" &&
            git -C "$src" checkout -q FETCH_HEAD; } >/dev/null 2>&1 ||
            { rm -rf "$src" && zz-log w "Could not fetch devcontainer-builder at ${CODER_DEVCONTAINER_BUILDER_REF}." && return 1; }
        tar -C "$src/templates/coder-kubernetes" -cf - . |
            kubectl -n "$CODER_NAMESPACE" exec -i deploy/coder -- sh -c 'rm -rf /tmp/dcb && mkdir -p /tmp/dcb && tar -xf - -C /tmp/dcb'
        rm -rf "$src"
        vars="--var namespace=${WORKSPACE_NAMESPACE} --var devcontainer_builder_endpoint=http://devcontainer-builder.devcontainer-builder.svc.cluster.local:8080 --var image_pull_secret_name=devcontainer-images"
        printf '%s\n' "$token" | kubectl -n "$CODER_NAMESPACE" exec -i deploy/coder -- sh -c "
      read -r CODER_SESSION_TOKEN; export CODER_SESSION_TOKEN CODER_URL=http://127.0.0.1:8080
      coder templates push kubernetes-devcontainer -d /tmp/dcb -y ${vars}"
    else
        # init, then patch the starter inside the pod: working icons for CPU, volume size and
        # repository (the CPU emoji 404s), and VS Code Desktop as an IDE beside code-server
        # stdin: the token line, then the patch for main.tf
        { printf '%s\n' "$token"; cat "$HELM_DIR/devcontainer-vscode.tf"; } | kubectl -n "$CODER_NAMESPACE" exec -i deploy/coder -- sh -c '
      read -r CODER_SESSION_TOKEN; export CODER_SESSION_TOKEN CODER_URL=http://127.0.0.1:8080
      cat >/tmp/devcontainer-vscode.tf
      rm -rf /tmp/devcontainer && coder templates init --id kubernetes-devcontainer /tmp/devcontainer &&
      sed -i -e "s#/emojis/1f5a5.png#/emojis/1f4bb.png#" -e "s#/emojis/1f4be.png#/icon/database.svg#" \
        -e "s#^\( *\)display_name = \"Repository (auto)\"#\1display_name = \"Repository (auto)\"\n\1icon         = \"/icon/git.svg\"#" /tmp/devcontainer/main.tf &&
      cat /tmp/devcontainer-vscode.tf >>/tmp/devcontainer/main.tf &&
      coder templates push devcontainer -d /tmp/devcontainer -y --name '"$TEMPLATE_REV"' \
        --var namespace='"$WORKSPACE_NAMESPACE"' --var use_kubeconfig=false'
    fi
}

up() {
    local db_password db_storage db_values wildcard wildcard_host wildcard_url access_url host values_file chart_version access middlewares
    local admin_email admin_user admin_password

    eval "$(kube-require)"

    # --- repositories and namespace
    zz-log i "Adding the Helm repositories (Bitnami for PostgreSQL, Coder for the chart)..."
    helm-repo bitnami https://charts.bitnami.com/bitnami app-coder https://helm.coder.com/v2

    # --- PostgreSQL (helm/postgresql-values.yaml)
    # alphanumeric only, so it can sit in the connection URL unescaped
    db_password="$(zz-persist -S -g 24 CODER_DB_PASSWORD "${CODER_DB_PASSWORD:-}")"
    db_storage="${CODER_DB_STORAGE:-10Gi}"

    zz-log i "Installing PostgreSQL (coder-db)..."
    db_values="$(mktemp)"
    yaml-render "$HELM_DIR/postgresql-values.yaml" db_password="$db_password" db_storage="$db_storage" >"$db_values"
    helm-install coder coder-db bitnami/postgresql --values "$db_values" --wait || { rm -f "$db_values" && exit 1; }
    rm -f "$db_values"

    kubectl -n "$CODER_NAMESPACE" create secret generic coder-db-url \
        --from-literal=url="postgres://coder:${db_password}@coder-db-postgresql.${CODER_NAMESPACE}.svc.cluster.local:5432/coder?sslmode=disable" \
        --dry-run=client -o yaml | kubectl apply -f -

    # --- Coder (helm/coder-values.yaml, or coder-values-wildcard.yaml)
    # Exposed through k3s's Traefik (ingress class traefik, ports 80/443). The cookie
    # Coder sets is scoped to the wildcard domain, so the dashboard host must sit
    # under it: both come from one domain (vps-system's SYSTEM_EXTERNAL_DOMAIN, else nip.io).
    # The route (public or internal, never both) and the domain come from the system config
    # (vps-access): public = Traefik 80/443 on the server IP; internal = a host on the internal domain
    # behind the internal-only middleware (internal network clients only). Plain HTTP either way.
    eval "$(vps-network access-route coder)"
    access="$route_access" middlewares="$route_middlewares" wildcard="$route_domain"
    [ -n "$wildcard" ] || { zz-log e "No domain for Coder: set SYSTEM_EXTERNAL_DOMAIN / SYSTEM_INTERNAL_DOMAIN (or install a network)." && exit 1; }
    access_url="http://coder.${wildcard}"
    host="${access_url#*://}"
    host="${host%%[:/]*}"
    values_file="$(mktemp)"
    if [ -n "$wildcard" ]; then
        wildcard_host="*.${wildcard}"
        wildcard_url="$wildcard_host"
        yaml-render "$HELM_DIR/coder-values-wildcard.yaml" access_url="$access_url" host="$host" wildcard_host="$wildcard_host" wildcard_url="$wildcard_url" middlewares="$middlewares" >"$values_file"
    else
        yaml-render "$HELM_DIR/coder-values.yaml" access_url="$access_url" host="$host" middlewares="$middlewares" >"$values_file"
    fi
    chart_version="${CODER_CHART_VERSION:+--version ${CODER_CHART_VERSION}}"

    zz-log i "Installing/upgrading Coder (access URL ${access_url})..."
    # shellcheck disable=SC2086
    helm-install "$CODER_NAMESPACE" coder app-coder/coder --values "$values_file" $chart_version ||
        { rm -f "$values_file" && exit 1; }
    rm -f "$values_file"

    kube-rollout -t 10m "$CODER_NAMESPACE" coder ||
        { zz-log e "Re-run: sudo vps-setup --only-app-coder" && exit 1; }

    ensure_workspace_namespace

    # charts first: the platform comes up even if the admin/template steps below only warn
    install_devcontainer_builder || zz-log w "devcontainer-builder / registry setup incomplete (see above); re-run: sudo vps-setup --only-app-coder"

    # --- admin user and template
    admin_email="${CODER_ADMIN_EMAIL:-admin@${wildcard:-coder.local}}"
    admin_user="${CODER_ADMIN_USERNAME:-admin}"
    admin_password="$(zz-persist -S -g 24 CODER_ADMIN_PASSWORD "${CODER_ADMIN_PASSWORD:-}")"
    zz-persist -S CODER_ADMIN_EMAIL "$admin_email"
    zz-persist -S CODER_ADMIN_USERNAME "$admin_user"
    bootstrap_coder "$admin_email" "$admin_user" "$admin_password"

    zz-log s "Coder installed: ${access_url} (via Traefik). Admin ${admin_email}; password saved to ${ZZ_SECRETS_FILE}."
}

down() {
    eval "$(kube-require -d)"
    zz-log w "Removing the coder namespace also deletes the PostgreSQL volume: all Coder data is lost."
    kube-teardown "$CODER_NAMESPACE" coder
    zz-persist -S -q -u "CODER_DB_PASSWORD CODER_ADMIN_PASSWORD CODER_ADMIN_EMAIL CODER_ADMIN_USERNAME"
    zz-log s "Coder removed."
}

summary() {
    local host access pub="" int="" reg="" ip

    # Opt-in step: say nothing on a host that never installed it.
    command -v kubectl >/dev/null 2>&1 && kubectl get namespace "$CODER_NAMESPACE" >/dev/null 2>&1 || return 0
    host="$(kubectl -n "$CODER_NAMESPACE" get ingress coder -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || true)"
    access="$(vps-network visibility coder)"
    if [ "$access" = "internal" ]; then
        int="http://${host:-<coder host>} (80/443, internal network clients only)"
    else
        pub="http://${host:-<coder host>} (through Traefik on 80/443)"
    fi
    if kubectl -n devcontainer-builder get deploy/registry >/dev/null 2>&1; then
        ip="$(hostname -I | awk '{print $1}')"
        reg="image registry ${ip}:${REGISTRY_PORT} (in-cluster, no login; catalog http://${ip}:${REGISTRY_PORT}/v2/_catalog)"
    fi
    vps-network summary-block Coder "$pub" "$int" "${reg:--}" \
        "user:     $(zz-persist -S -r -v 'not set - run app-coder/run.sh' CODER_ADMIN_EMAIL)" \
        "password: $(zz-persist -S -r -v 'not set - run app-coder/run.sh' CODER_ADMIN_PASSWORD)" \
        "(saved to ${ZZ_SECRETS_FILE}; template: kubernetes-devcontainer or devcontainer)"
}

case "${1:-}" in
    up | down) "$1" ;;
    summary) if command -v summary >/dev/null 2>&1; then summary; fi ;;
    *) zz-log e "Usage: $0 up|down|summary" && exit 1 ;;
esac
