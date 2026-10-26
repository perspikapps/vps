#!/bin/sh
# Coder on the cluster, following https://coder.com/docs/install/server/rancher
# (namespace, Bitnami PostgreSQL, db-url Secret, upstream chart) but with the
# helm CLI instead of the Rancher UI. Env vars: see README.

set -eu
zz-use zz-colors zz-log zz-persist yaml-render kube-progress kube-diagnose kube-teardown perspikapps/vps/vps-network
# shellcheck disable=SC1091
. zz-colors

CODER_NAMESPACE=coder
# Where workspaces run: one namespace for the template's `namespace` variable, the pull secret and
# the RBAC (the Coder chart's own permissions cover only its release namespace). The platform page's name.
WORKSPACE_NAMESPACE="${CODER_WORKSPACE_NAMESPACE:-coder-workspaces}"
printf '%s\n' "$WORKSPACE_NAMESPACE" | grep -Eq '^[a-z0-9]([-a-z0-9]*[a-z0-9])?$' ||
    { zz-log e "[vps-setup] CODER_WORKSPACE_NAMESPACE must be a lowercase RFC 1123 label (got '${WORKSPACE_NAMESPACE}')." && exit 1; }
REGISTRY_PORT="$(vps-network port devcontainer_registry)"
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
CODER_API=http://127.0.0.1:18080/api/v2
# Chart values and manifests, rendered with yaml-render (see helm/).
HELM_DIR="$(cd "$(dirname "$0")" && pwd)/helm"

# The workspace namespace, with rights for Coder's service account (coder:coder) to run workspaces in it:
# the template creates a Deployment and a PVC (and the builder template reads pods/events).
ensure_workspace_namespace() {
    local coder_namespace="$CODER_NAMESPACE"

    [ "$WORKSPACE_NAMESPACE" != "$CODER_NAMESPACE" ] || return 0
    zz-log i "[vps-setup] Preparing the workspace namespace '${WORKSPACE_NAMESPACE}' (Coder's service account may manage workspaces there)..."
    kubectl create namespace "$WORKSPACE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    yaml-render "$HELM_DIR/workspace-rbac.yaml" coder_namespace="$coder_namespace" | kubectl apply -n "$WORKSPACE_NAMESPACE" -f -
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
    run_bootstrap_steps "$email" "$user" "$pw" || zz-log w "[vps-setup] Coder admin/template bootstrap incomplete (see above); finish it in the UI."
    kill "$pf_pid" 2>/dev/null || true
}

run_bootstrap_steps() {
    local email="$1" user="$2" pw="$3" code token

    curl -fs -o /dev/null "$CODER_API/buildinfo" || { zz-log w "[vps-setup] Coder API not reachable through the port-forward." && return 1; }

    code="$(curl -s -o /dev/null -w '%{http_code}' "$CODER_API/users/first")"
    if [ "$code" = "404" ]; then
        zz-log i "[vps-setup] Creating the Coder admin user '${user}'..."
        jq -n --arg e "$email" --arg u "$user" --arg p "$pw" '{email: $e, username: $u, name: $u, password: $p, trial: false}' |
            curl -fsS -o /dev/null -X POST -H 'Content-Type: application/json' -d @- "$CODER_API/users/first" ||
            { zz-log w "[vps-setup] Creating the first Coder user failed (POST /users/first)." && return 1; }
    fi

    token="$(jq -n --arg e "$email" --arg p "$pw" '{email: $e, password: $p}' |
        curl -fsS -X POST -H 'Content-Type: application/json' -d @- "$CODER_API/users/login" 2>/dev/null | jq -r '.session_token // empty')" || true
    [ -n "$token" ] || { zz-log w "[vps-setup] Could not log in as '${email}' (password changed since?); skipping the template." && return 1; }

    # the platform (devcontainer-builder + registry) is installed before the admin step;
    # its template is pushed only when it is up and the template repo ref is pinned
    if [ "${BUILDER_READY:-}" = "1" ]; then
        if printf '%s\n' "${DEVCONTAINER_BUILDER_REF:-}" | grep -Eq '^[0-9A-Za-z][0-9A-Za-z._/-]*$'; then
            push_coder_template "$token" kubernetes-devcontainer || { zz-log w "[vps-setup] Pushing the kubernetes-devcontainer template failed (see above)." && return 1; }
            return 0
        fi
        zz-log w "[vps-setup] devcontainer-builder is installed, but its template is third-party code and must be pinned: set DEVCONTAINER_BUILDER_REF (a tag or commit of github.com/DeepSpaceCartel/devcontainer-builder). Using the Envbuilder starter instead."
    fi
    push_coder_template "$token" envbuilder || { zz-log w "[vps-setup] Pushing the Envbuilder 'devcontainer' template failed (see above)." && return 1; }
    zz-log i "[vps-setup] Template pushed."
}

# In-cluster registry for the built images (anonymous, plain HTTP, no TLS): registry:2 with a PVC, on
# hostPort 5000 so that both BuildKit (pods) and containerd (kubelet, which cannot resolve cluster DNS)
# reach it as <node ip>:5000 (helm/registry.yaml). Port 5000 is declared "private" in package.json, so
# ufw and the FORWARD guard keep it off the internet. containerd needs a registries.yaml mirror to pull
# over HTTP.
deploy_local_registry() {
    local addr="$1" cfg=/etc/rancher/k3s/registries.yaml registry_port="$REGISTRY_PORT" i

    zz-log i "[vps-setup] Deploying the in-cluster image registry at ${addr}..."
    kubectl create namespace devcontainer-builder --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace devcontainer-builder pod-security.kubernetes.io/enforce=privileged --overwrite
    yaml-render "$HELM_DIR/registry.yaml" registry_port="$registry_port" | kubectl apply -n devcontainer-builder -f -
    kubectl -n devcontainer-builder rollout status deploy/registry --timeout=5m
    vps-network reapply-guard
    if [ ! -f "$cfg" ]; then
        zz-log i "[vps-setup] Letting containerd pull ${addr} over HTTP (${cfg}); restarting k3s (running pods keep running)..."
        printf 'mirrors:\n  "%s":\n    endpoint:\n      - "http://%s"\n' "$addr" "$addr" >"$cfg"
        systemctl restart k3s
        for i in $(seq 1 60); do
            kubectl get --raw /readyz >/dev/null 2>&1 && break
            sleep 2
        done
    elif ! grep -qF "$addr" "$cfg"; then
        zz-log w "[vps-setup] ${cfg} exists without ${addr}: add a mirror with endpoint http://${addr} yourself, then restart k3s, or workspaces cannot pull the built images."
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
    yaml-render "$HELM_DIR/buildkit.yaml" config_sha="$config_sha" | kubectl apply -n devcontainer-builder -f -
    kubectl -n devcontainer-builder rollout status deploy/buildkit --timeout=5m
}

# devcontainer-builder (https://deepspacecartel.github.io/devcontainer-builder/getting-started/platform/):
# builds a repo's devcontainer.json into an image pushed to a registry, with its own BuildKit (needs a
# privileged namespace). Third-party chart: an unset DEVCONTAINER_BUILDER_VERSION resolves to the latest
# and is logged so it can be pinned. The registry is the external one when DEVCONTAINER_REGISTRY_* are
# set, else the in-cluster one. Sets BUILDER_READY=1 for the template step.
install_devcontainer_builder() {
    local values rc=0 chart=oci://ghcr.io/deepspacecartel/charts/devcontainer-builder version="${DEVCONTAINER_BUILDER_VERSION:-}"
    local registry mapped auth_user auth_pw node_ip insecure_registries='[]' insecure_host="" registry_auth status

    if [ -z "$version" ]; then
        version="$(helm show chart "$chart" 2>/dev/null | awk '/^version:/ {print $2; exit}')" || true
        [ -n "$version" ] || { zz-log w "[vps-setup] Could not resolve the latest devcontainer-builder chart version." && return 1; }
        zz-log w "[vps-setup] DEVCONTAINER_BUILDER_VERSION not set: installing the latest chart, ${version}. Pin it with DEVCONTAINER_BUILDER_VERSION=${version}."
    fi
    if [ -n "${DEVCONTAINER_REGISTRY_TOKEN:-}" ] && [ -n "${DEVCONTAINER_REGISTRY_USER:-}" ] && [ -n "${DEVCONTAINER_REGISTRY_ORG:-}" ]; then
        registry="${DEVCONTAINER_REGISTRY:-ghcr.io}"
        mapped="${registry}/${DEVCONTAINER_REGISTRY_ORG}"
        auth_user="$DEVCONTAINER_REGISTRY_USER"
        auth_pw="$DEVCONTAINER_REGISTRY_TOKEN"
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
    zz-log i "[vps-setup] Installing devcontainer-builder chart ${version} (images go to ${mapped})..."
    kubectl create namespace devcontainer-builder --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace devcontainer-builder pod-security.kubernetes.io/enforce=privileged --overwrite
    # A release left "failed" by an earlier attempt makes `helm upgrade` choke on resources it lists but
    # that are gone. Forget the record only: `helm uninstall` would delete what it lists, which can
    # include this namespace (older attempts had the chart own it) and with it the registry and its images.
    status="$(helm status devcontainer-builder -n devcontainer-builder -o json 2>/dev/null | jq -r '.info.status // empty')" || status=""
    if [ -n "$status" ] && [ "$status" != "deployed" ]; then
        zz-log w "[vps-setup] Dropping the record of the ${status} devcontainer-builder release from an earlier attempt (resources are kept)."
        kubectl -n devcontainer-builder delete secret -l owner=helm,name=devcontainer-builder
    fi
    deploy_buildkit "${insecure_host}" || return 1
    registry_auth="$(jq -nc --arg reg "$registry" --arg user "$auth_user" --arg tok "$auth_pw" \
        'if $user == "" then [] else [{registry: $reg, username: $user, password: $tok}] end')"
    values="$(mktemp)"
    yaml-render "$HELM_DIR/devcontainer-builder-values.yaml" mapped="$mapped" registry_auth="$registry_auth" insecure_registries="$insecure_registries" >"$values"
    kube-progress devcontainer-builder "devcontainer-builder install" \
        helm upgrade --install devcontainer-builder "$chart" \
        --version "$version" -n devcontainer-builder --values "$values" --wait --timeout 10m || rc=$?
    rm -f "$values"
    if [ "$rc" -ne 0 ]; then
        kube-diagnose devcontainer-builder
        return "$rc"
    fi
    # workspaces pull the built images with this secret (a dummy login when the registry is anonymous)
    kubectl -n "$WORKSPACE_NAMESPACE" create secret docker-registry devcontainer-images \
        --docker-server="$registry" --docker-username="${auth_user:-anonymous}" --docker-password="${auth_pw:-anonymous}" \
        --dry-run=client -o yaml | kubectl apply -f -
    BUILDER_READY=1
    DEVCONTAINER_IMAGE_REGISTRY="$mapped"
}

# push_coder_template TOKEN KIND: pushes once (an existing template is left as is), from inside
# the Coder pod (its `coder` CLI matches the server). Token goes in on stdin, not argv.
push_coder_template() {
    local token="$1" kind="$2" name vars src tpl ver cur

    if [ "$kind" = "kubernetes-devcontainer" ]; then name=kubernetes-devcontainer; else name=devcontainer; fi
    tpl="$(curl -fsS -H "Coder-Session-Token: $token" "$CODER_API/templates" | jq -c --arg n "$name" '.[] | select(.name == $n)')" || tpl=""
    if [ -n "$tpl" ]; then
        ver="$(printf '%s' "$tpl" | jq -r '.active_version_id')"
        cur="$(curl -fsS -H "Coder-Session-Token: $token" "$CODER_API/templateversions/${ver}/variables" 2>/dev/null | jq -r '.[] | select(.name == "namespace") | .value // empty')" || cur=""
        if [ "$cur" = "$WORKSPACE_NAMESPACE" ]; then
            zz-log i "[vps-setup] Template '${name}' already exists (namespace ${cur}); leaving it as is."
            return 0
        fi
        zz-log i "[vps-setup] Template '${name}' uses namespace '${cur:-unknown}', not '${WORKSPACE_NAMESPACE}': pushing a new version."
    fi
    zz-log i "[vps-setup] Creating the '${name}' template..."
    if [ "$kind" = "kubernetes-devcontainer" ]; then
        # the template repo at the pinned tag/commit, not its default branch
        src="$(mktemp -d)"
        { git -C "$src" init -q && git -C "$src" fetch -q --depth 1 https://github.com/DeepSpaceCartel/devcontainer-builder.git "$DEVCONTAINER_BUILDER_REF" &&
            git -C "$src" checkout -q FETCH_HEAD; } >/dev/null 2>&1 ||
            { rm -rf "$src" && zz-log w "[vps-setup] Could not fetch devcontainer-builder at ${DEVCONTAINER_BUILDER_REF}." && return 1; }
        tar -C "$src/templates/coder-kubernetes" -cf - . |
            kubectl -n "$CODER_NAMESPACE" exec -i deploy/coder -- sh -c 'rm -rf /tmp/dcb && mkdir -p /tmp/dcb && tar -xf - -C /tmp/dcb'
        rm -rf "$src"
        vars="--var namespace=${WORKSPACE_NAMESPACE} --var devcontainer_builder_endpoint=http://devcontainer-builder.devcontainer-builder.svc.cluster.local:8080 --var image_pull_secret_name=devcontainer-images"
        printf '%s\n' "$token" | kubectl -n "$CODER_NAMESPACE" exec -i deploy/coder -- sh -c "
      read -r CODER_SESSION_TOKEN; export CODER_SESSION_TOKEN CODER_URL=http://127.0.0.1:8080
      coder templates push kubernetes-devcontainer -d /tmp/dcb -y ${vars}"
    else
        printf '%s\n' "$token" | kubectl -n "$CODER_NAMESPACE" exec -i deploy/coder -- sh -c '
      read -r CODER_SESSION_TOKEN; export CODER_SESSION_TOKEN CODER_URL=http://127.0.0.1:8080
      coder templates init --id kubernetes-devcontainer /tmp/devcontainer &&
      coder templates push devcontainer -d /tmp/devcontainer -y \
        --var namespace='"$WORKSPACE_NAMESPACE"' --var use_kubeconfig=false'
    fi
}

up() {
    local db_password db_storage db_values rc=0 wildcard wildcard_host wildcard_url access_url host values_file chart_version access entrypoints tls scheme port_suffix
    local admin_email admin_user admin_password

    command -v kubectl >/dev/null 2>&1 || { zz-log e "[vps-setup] kubectl not found; run vps-k3s/run.sh first." && exit 1; }
    command -v helm >/dev/null 2>&1 || { zz-log e "[vps-setup] helm not found; run vps-k3s/run.sh first." && exit 1; }

    # --- repositories and namespace
    zz-log i "[vps-setup] Adding the Helm repositories (Bitnami for PostgreSQL, Coder for the chart)..."
    helm repo add bitnami https://charts.bitnami.com/bitnami --force-update >/dev/null
    helm repo add vps-coder https://helm.coder.com/v2 --force-update >/dev/null
    helm repo update bitnami vps-coder >/dev/null || { zz-log e "[vps-setup] Could not fetch the Bitnami/Coder chart indexes." && exit 1; }

    kubectl create namespace "$CODER_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    # --- PostgreSQL (helm/postgresql-values.yaml)
    # alphanumeric only, so it can sit in the connection URL unescaped
    db_password="$(zz-persist -f "$VPS_SECRETS_FILE" -s -g 24 CODER_DB_PASSWORD "${CODER_DB_PASSWORD:-}")"
    db_storage="${CODER_DB_STORAGE:-10Gi}"

    zz-log i "[vps-setup] Installing PostgreSQL (coder-db)..."
    db_values="$(mktemp)"
    yaml-render "$HELM_DIR/postgresql-values.yaml" db_password="$db_password" db_storage="$db_storage" >"$db_values"
    kube-progress "$CODER_NAMESPACE" "Coder PostgreSQL" \
        helm upgrade --install coder-db bitnami/postgresql -n "$CODER_NAMESPACE" --values "$db_values" --wait --timeout 10m || rc=$?
    rm -f "$db_values"
    if [ "$rc" -ne 0 ]; then
        kube-diagnose "$CODER_NAMESPACE"
        exit "$rc"
    fi

    kubectl -n "$CODER_NAMESPACE" create secret generic coder-db-url \
        --from-literal=url="postgres://coder:${db_password}@coder-db-postgresql.${CODER_NAMESPACE}.svc.cluster.local:5432/coder?sslmode=disable" \
        --dry-run=client -o yaml | kubectl apply -f -

    # --- Coder (helm/coder-values.yaml, or coder-values-wildcard.yaml)
    # Exposed through k3s's Traefik (ingress class traefik, ports 80/443). The cookie
    # Coder sets is scoped to the wildcard domain, so the dashboard host must sit
    # under it: both come from one domain (vps-system's WILDCARD_DOMAIN, else nip.io).
    # vps-access (or CODER_ACCESS) picks public or internal, never both: public = Traefik 80/443 on the
    # server IP; internal = Traefik's private "internal" (HTTP) port on the
    # Tailscale/Cloudflare address. Plain HTTP either way, like public.
    access="$(vps-network visibility coder)"
    case "$access" in
        public) entrypoints="web,websecure" tls="false" scheme="http" port_suffix="" ;;
        internal) entrypoints="internal,internalsecure" tls="false" scheme="http" port_suffix=":$(vps-network port traefik_internal_http)" ;;
        *) zz-log e "[vps-setup] CODER_ACCESS must be public or internal (got '${access}')." && exit 1 ;;
    esac
    wildcard="$(vps-network access-domain "$access")" || exit 1
    access_url="${CODER_ACCESS_URL:-${wildcard:+${scheme}://coder.${wildcard}${port_suffix}}}"
    [ -n "$access_url" ] || { zz-log e "[vps-setup] No access URL: set CODER_ACCESS_URL or WILDCARD_DOMAIN." && exit 1; }
    host="${access_url#*://}"
    host="${host%%[:/]*}"
    values_file="$(mktemp)"
    if [ -n "$wildcard" ]; then
        wildcard_host="*.${wildcard}"
        wildcard_url="${wildcard_host}${port_suffix}"
        yaml-render "$HELM_DIR/coder-values-wildcard.yaml" access_url="$access_url" host="$host" wildcard_host="$wildcard_host" wildcard_url="$wildcard_url" entrypoints="$entrypoints" tls="$tls" >"$values_file"
    else
        yaml-render "$HELM_DIR/coder-values.yaml" access_url="$access_url" host="$host" entrypoints="$entrypoints" tls="$tls" >"$values_file"
    fi
    chart_version="${CODER_CHART_VERSION:+--version ${CODER_CHART_VERSION}}"

    zz-log i "[vps-setup] Installing/upgrading Coder (access URL ${access_url})..."
    rc=0
    # shellcheck disable=SC2086
    kube-progress "$CODER_NAMESPACE" "Coder install" \
        helm upgrade --install coder vps-coder/coder -n "$CODER_NAMESPACE" --values "$values_file" \
        $chart_version --timeout 10m || rc=$?
    rm -f "$values_file"
    if [ "$rc" -ne 0 ]; then
        kube-diagnose "$CODER_NAMESPACE"
        exit "$rc"
    fi

    if ! kube-progress "$CODER_NAMESPACE" "Coder rollout" kubectl -n "$CODER_NAMESPACE" rollout status deploy/coder --timeout=10m; then
        kube-diagnose "$CODER_NAMESPACE"
        zz-log e "[vps-setup] Coder did not become ready in time; re-run: sudo vps-setup --only-vps-coder" && exit 1
    fi

    ensure_workspace_namespace

    # charts first: the platform comes up even if the admin/template steps below only warn
    install_devcontainer_builder || zz-log w "[vps-setup] devcontainer-builder / registry setup incomplete (see above); re-run: sudo vps-setup --only-vps-coder"

    # --- admin user and template
    admin_email="${CODER_ADMIN_EMAIL:-admin@${wildcard:-coder.local}}"
    admin_user="${CODER_ADMIN_USERNAME:-admin}"
    admin_password="$(zz-persist -f "$VPS_SECRETS_FILE" -s -g 24 CODER_ADMIN_PASSWORD "${CODER_ADMIN_PASSWORD:-}")"
    zz-persist -s -f "$VPS_SECRETS_FILE" CODER_ADMIN_EMAIL "$admin_email"
    zz-persist -s -f "$VPS_SECRETS_FILE" CODER_ADMIN_USERNAME "$admin_user"
    bootstrap_coder "$admin_email" "$admin_user" "$admin_password"

    zz-log s "[vps-setup] Coder installed: ${access_url} (via Traefik). Admin ${admin_email}; password saved to ${VPS_SECRETS_FILE}."
}

down() {
    command -v kubectl >/dev/null 2>&1 || { zz-log w "[vps-setup] kubectl not found; nothing to remove." && return 0; }
    zz-log w "[vps-setup] Removing the coder namespace also deletes the PostgreSQL volume: all Coder data is lost."
    kube-teardown "$CODER_NAMESPACE" coder
    zz-persist -q -f "$VPS_SECRETS_FILE" -u CODER_DB_PASSWORD
    zz-persist -q -f "$VPS_SECRETS_FILE" -u CODER_ADMIN_PASSWORD
    zz-persist -q -f "$VPS_SECRETS_FILE" -u CODER_ADMIN_EMAIL
    zz-persist -q -f "$VPS_SECRETS_FILE" -u CODER_ADMIN_USERNAME
    zz-log s "[vps-setup] Coder removed."
}

summary() {
    local host

    # Opt-in step: say nothing on a host that never installed it.
    command -v kubectl >/dev/null 2>&1 && kubectl get namespace "$CODER_NAMESPACE" >/dev/null 2>&1 || return 0
    host="$(kubectl -n "$CODER_NAMESPACE" get ingress coder -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || true)"
    cat <<EOF
 Coder:               http://${host:-<coder host>} (through Traefik on 80/443 - public)
                       user:     $(zz-persist -f "$VPS_SECRETS_FILE" -r CODER_ADMIN_EMAIL | grep . || echo 'not set - run vps-coder/run.sh')
                       password: $(zz-persist -f "$VPS_SECRETS_FILE" -r CODER_ADMIN_PASSWORD | grep . || echo 'not set - run vps-coder/run.sh')
                       (saved to ${VPS_SECRETS_FILE}; template: kubernetes-devcontainer or devcontainer)
EOF
    if kubectl -n devcontainer-builder get deploy/registry >/dev/null 2>&1; then
        echo " Image registry:      $(hostname -I | awk '{print $1}'):${REGISTRY_PORT} (in-cluster, private; catalog: http://$(vps-network summary-host):${REGISTRY_PORT}/v2/_catalog)"
    fi
}

case "${1:-}" in
    up | down) "$1" ;;
    summary) if command -v summary >/dev/null 2>&1; then summary; fi ;;
    *) zz-log e "Usage: $0 up|down|summary" && exit 1 ;;
esac
