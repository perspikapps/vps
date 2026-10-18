#!/usr/bin/env bash
# Coder on the cluster, following https://coder.com/docs/install/server/rancher
# (namespace, Bitnami PostgreSQL, db-url Secret, upstream chart) but with the
# helm CLI instead of the Rancher UI. Env vars: see README.

set -euo pipefail
zz-use "perspikapps/vps/vps-common@${ZZ_SETUP_REF:-main}" zz-persist
# shellcheck disable=SC1091
. vps-common

# vps-common comes from zz-use's download cache, one slot per repo+ref: running a
# branch fetches its own vps-common (zz-use pins it to ZZ_SETUP_REF); an older copy is used otherwise.
declare -F wildcard_domain >/dev/null || {
  zz-log e "[vps-setup] The cached vps-common is older than this step. Run it from the branch:" \
       "sudo ZZ_SETUP_REF=<ref> zz-setup perspikapps/vps -o vps-coder"
  exit 1
}

CODER_NAMESPACE=coder
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
CODER_API=http://127.0.0.1:18080/api/v2

# Creates the first admin (once) and the "devcontainer" template (once), through
# a port-forward to the pod: Traefik and DNS are not needed, and the template
# comes from the starter embedded in the server's own `coder` binary, so it
# always matches the installed version. Everything here is best effort: a
# failure warns and leaves a working Coder (create them in the UI instead).
bootstrap_coder() {
  local email="$1" user="$2" pw="$3" i code token pf_pid
  kubectl -n "$CODER_NAMESPACE" port-forward deploy/coder 18080:8080 >/dev/null 2>&1 &
  pf_pid=$!
  for i in $(seq 1 30); do
    curl -fs -o /dev/null "$CODER_API/buildinfo" && break
    sleep 2
  done
  _coder_bootstrap_steps "$email" "$user" "$pw" || zz-log w "[vps-setup] Coder admin/template bootstrap incomplete (see above); finish it in the UI."
  kill "$pf_pid" 2>/dev/null || true
}

_coder_bootstrap_steps() {
  local email="$1" user="$2" pw="$3" code token
  curl -fs -o /dev/null "$CODER_API/buildinfo" || { zz-log w "[vps-setup] Coder API not reachable through the port-forward."; return 1; }

  code="$(curl -s -o /dev/null -w '%{http_code}' "$CODER_API/users/first")"
  if [[ "$code" == "404" ]]; then
    zz-log i "[vps-setup] Creating the Coder admin user '${user}'..."
    jq -n --arg e "$email" --arg u "$user" --arg p "$pw" '{email: $e, username: $u, name: $u, password: $p, trial: false}' |
      curl -fsS -o /dev/null -X POST -H 'Content-Type: application/json' -d @- "$CODER_API/users/first" || return 1
  fi

  token="$(jq -n --arg e "$email" --arg p "$pw" '{email: $e, password: $p}' |
    curl -fsS -X POST -H 'Content-Type: application/json' -d @- "$CODER_API/users/login" 2>/dev/null | jq -r '.session_token // empty')" || true
  [[ -n "$token" ]] || { zz-log w "[vps-setup] Could not log in as '${email}' (password changed since?); skipping the template."; return 1; }

  if [[ -n "${DEVCONTAINER_REGISTRY_TOKEN:-}" && -n "${DEVCONTAINER_REGISTRY_USER:-}" && -n "${DEVCONTAINER_REGISTRY_ORG:-}" ]]; then
    if [[ "${DEVCONTAINER_BUILDER_VERSION:-}" =~ ^[0-9A-Za-z][0-9A-Za-z.+-]*$ && "${DEVCONTAINER_BUILDER_REF:-}" =~ ^[0-9A-Za-z][0-9A-Za-z._/-]*$ ]]; then
      install_devcontainer_builder || return 1
      push_coder_template "$token" kubernetes-devcontainer || return 1
      return 0
    fi
    zz-log w "[vps-setup] Registry credentials are set but devcontainer-builder is third-party code and must be pinned: set DEVCONTAINER_BUILDER_VERSION (chart) and DEVCONTAINER_BUILDER_REF (template tag/commit). Using the Envbuilder starter instead."
  fi
  push_coder_template "$token" envbuilder || return 1
}

# devcontainer-builder (https://deepspacecartel.github.io/devcontainer-builder/getting-started/platform/):
# the service that builds a repo's devcontainer.json into an image pushed to a registry, with
# its own BuildKit (needs a privileged namespace). Third-party: the chart version is pinned.
install_devcontainer_builder() {
  local values rc=0 registry="${DEVCONTAINER_REGISTRY:-ghcr.io}"
  zz-log i "[vps-setup] Installing devcontainer-builder chart ${DEVCONTAINER_BUILDER_VERSION} (registry ${registry}/${DEVCONTAINER_REGISTRY_ORG})..."
  kubectl create namespace devcontainer-builder --dry-run=client -o yaml | kubectl apply -f -
  kubectl label namespace devcontainer-builder pod-security.kubernetes.io/enforce=privileged --overwrite
  values="$(mktemp)"
  jq -n --arg reg "$registry" --arg user "$DEVCONTAINER_REGISTRY_USER" --arg tok "$DEVCONTAINER_REGISTRY_TOKEN" --arg org "$DEVCONTAINER_REGISTRY_ORG" \
    '{buildkit: {deploy: {enabled: true}},
      registryAuth: {registries: [{registry: $reg, username: $user, password: $tok}]},
      registryMapping: {rules: [{hostMatch: "github.com", registry: ($reg + "/" + $org)}]}}' >"$values"
  run_with_progress devcontainer-builder "devcontainer-builder install" \
    helm upgrade --install devcontainer-builder oci://ghcr.io/deepspacecartel/charts/devcontainer-builder \
    --version "$DEVCONTAINER_BUILDER_VERSION" -n devcontainer-builder --values "$values" --wait --timeout 10m || rc=$?
  rm -f "$values"
  if [[ "$rc" -ne 0 ]]; then dump_diagnostics devcontainer-builder; return "$rc"; fi
  # workspaces pull the built images from the (possibly private) registry
  kubectl -n "$CODER_NAMESPACE" create secret docker-registry devcontainer-images \
    --docker-server="$registry" --docker-username="$DEVCONTAINER_REGISTRY_USER" --docker-password="$DEVCONTAINER_REGISTRY_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
}

# push_coder_template TOKEN KIND: pushes once (an existing template is left as is), from inside
# the Coder pod (its `coder` CLI matches the server). Token goes in on stdin, not argv.
push_coder_template() {
  local token="$1" kind="$2" name vars src
  if [[ "$kind" == "kubernetes-devcontainer" ]]; then name=kubernetes-devcontainer; else name=devcontainer; fi
  if curl -fsS -H "Coder-Session-Token: $token" "$CODER_API/templates" | jq -e --arg n "$name" '.[] | select(.name == $n)' >/dev/null; then
    zz-log i "[vps-setup] Template '${name}' already exists; leaving it as is."
    return 0
  fi
  zz-log i "[vps-setup] Creating the '${name}' template..."
  if [[ "$kind" == "kubernetes-devcontainer" ]]; then
    # the template repo at the pinned tag/commit, not its default branch
    src="$(mktemp -d)"
    { git -C "$src" init -q && git -C "$src" fetch -q --depth 1 https://github.com/DeepSpaceCartel/devcontainer-builder.git "$DEVCONTAINER_BUILDER_REF" \
      && git -C "$src" checkout -q FETCH_HEAD; } >/dev/null 2>&1 \
      || { rm -rf "$src"; zz-log w "[vps-setup] Could not fetch devcontainer-builder at ${DEVCONTAINER_BUILDER_REF}."; return 1; }
    tar -C "$src/templates/coder-kubernetes" -cf - . |
      kubectl -n "$CODER_NAMESPACE" exec -i deploy/coder -- sh -c 'rm -rf /tmp/dcb && mkdir -p /tmp/dcb && tar -xf - -C /tmp/dcb'
    rm -rf "$src"
    vars="--var namespace=${CODER_NAMESPACE} --var devcontainer_builder_endpoint=http://devcontainer-builder.devcontainer-builder.svc.cluster.local:8080 --var image_pull_secret_name=devcontainer-images"
    printf '%s\n' "$token" | kubectl -n "$CODER_NAMESPACE" exec -i deploy/coder -- sh -c "
      read -r CODER_SESSION_TOKEN; export CODER_SESSION_TOKEN CODER_URL=http://127.0.0.1:8080
      coder templates push kubernetes-devcontainer -d /tmp/dcb -y ${vars}"
  else
    printf '%s\n' "$token" | kubectl -n "$CODER_NAMESPACE" exec -i deploy/coder -- sh -c '
      read -r CODER_SESSION_TOKEN; export CODER_SESSION_TOKEN CODER_URL=http://127.0.0.1:8080
      coder templates init --id kubernetes-devcontainer /tmp/devcontainer &&
      coder templates push devcontainer -d /tmp/devcontainer -y \
        --var namespace='"$CODER_NAMESPACE"' --var use_kubeconfig=false'
  fi
}

up() {
command_exists kubectl || { zz-log e "[vps-setup] kubectl not found; run vps-k3s/run.sh first."; exit 1; }
command_exists helm || { zz-log e "[vps-setup] helm not found; run vps-k3s/run.sh first."; exit 1; }

zz-log i "[vps-setup] Adding the Helm repositories (Bitnami for PostgreSQL, Coder for the chart)..."
helm repo add bitnami https://charts.bitnami.com/bitnami --force-update >/dev/null
helm repo add vps-coder https://helm.coder.com/v2 --force-update >/dev/null
helm repo update bitnami vps-coder >/dev/null || { zz-log e "[vps-setup] Could not fetch the Bitnami/Coder chart indexes."; exit 1; }

kubectl create namespace "$CODER_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# alphanumeric only, so it can sit in the connection URL unescaped
DB_PASSWORD="$(vps_secret CODER_DB_PASSWORD)"
if [[ -z "$DB_PASSWORD" ]]; then
  DB_PASSWORD="$(random_password 24)"
  vps_secret_set CODER_DB_PASSWORD "$DB_PASSWORD"
fi

zz-log i "[vps-setup] Installing PostgreSQL (coder-db)..."
# bitnamilegacy/postgresql is the image the Coder doc uses; recent Bitnami
# charts refuse a non-Bitnami image unless allowInsecureImages is set.
DB_VALUES="$(mktemp)"
jq -n --arg pw "$DB_PASSWORD" --arg size "${CODER_DB_STORAGE:-10Gi}" \
  '{image: {repository: "bitnamilegacy/postgresql"}, global: {security: {allowInsecureImages: true}},
    auth: {username: "coder", password: $pw, database: "coder"}, persistence: {size: $size}}' >"$DB_VALUES"
rc=0
run_with_progress "$CODER_NAMESPACE" "Coder PostgreSQL" \
  helm upgrade --install coder-db bitnami/postgresql -n "$CODER_NAMESPACE" --values "$DB_VALUES" --wait --timeout 10m || rc=$?
rm -f "$DB_VALUES"
if [[ "$rc" -ne 0 ]]; then dump_diagnostics "$CODER_NAMESPACE"; exit "$rc"; fi

kubectl -n "$CODER_NAMESPACE" create secret generic coder-db-url \
  --from-literal=url="postgres://coder:${DB_PASSWORD}@coder-db-postgresql.${CODER_NAMESPACE}.svc.cluster.local:5432/coder?sslmode=disable" \
  --dry-run=client -o yaml | kubectl apply -f -

# Exposed through k3s's Traefik (ingress class traefik, ports 80/443). The cookie
# Coder sets is scoped to the wildcard domain, so the dashboard host must sit
# under it: both come from one domain (vps-system's WILDCARD_DOMAIN, else nip.io).
WILDCARD="$(wildcard_domain)"
ACCESS_URL="${CODER_ACCESS_URL:-${WILDCARD:+http://coder.${WILDCARD}}}"
[[ -n "$ACCESS_URL" ]] || { zz-log e "[vps-setup] No access URL: set CODER_ACCESS_URL or WILDCARD_DOMAIN."; exit 1; }
HOST="${ACCESS_URL#*://}"; HOST="${HOST%%[:/]*}"
VALUES_FILE="$(mktemp)"
jq -n --arg url "$ACCESS_URL" --arg host "$HOST" --arg wildcard "${WILDCARD:+*.${WILDCARD}}" \
  '{coder: {env: ([
      {name: "CODER_PG_CONNECTION_URL", valueFrom: {secretKeyRef: {name: "coder-db-url", key: "url"}}},
      {name: "CODER_ACCESS_URL", value: $url}]
      + (if $wildcard == "" then [] else [{name: "CODER_WILDCARD_ACCESS_URL", value: $wildcard}] end)),
    service: {type: "ClusterIP"},
    ingress: ({enable: true, className: "traefik", host: $host}
      + (if $wildcard == "" then {} else {wildcardHost: $wildcard} end))}}' >"$VALUES_FILE"
CHART_VERSION_ARG=()
[[ -z "${CODER_CHART_VERSION:-}" ]] || CHART_VERSION_ARG=(--version "$CODER_CHART_VERSION")

zz-log i "[vps-setup] Installing/upgrading Coder (access URL ${ACCESS_URL})..."
rc=0
run_with_progress "$CODER_NAMESPACE" "Coder install" \
  helm upgrade --install coder vps-coder/coder -n "$CODER_NAMESPACE" --values "$VALUES_FILE" \
  "${CHART_VERSION_ARG[@]}" --timeout 10m || rc=$?
rm -f "$VALUES_FILE"
if [[ "$rc" -ne 0 ]]; then dump_diagnostics "$CODER_NAMESPACE"; exit "$rc"; fi

if ! run_with_progress "$CODER_NAMESPACE" "Coder rollout" kubectl -n "$CODER_NAMESPACE" rollout status deploy/coder --timeout=10m; then
  dump_diagnostics "$CODER_NAMESPACE"
  zz-log e "[vps-setup] Coder did not become ready in time; re-run: sudo vps-setup --only-vps-coder"
  exit 1
fi

ADMIN_EMAIL="${CODER_ADMIN_EMAIL:-admin@${WILDCARD:-coder.local}}"
ADMIN_USER="${CODER_ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="$(vps_secret CODER_ADMIN_PASSWORD)"
if [[ -z "$ADMIN_PASSWORD" ]]; then
  ADMIN_PASSWORD="$(random_password 24)"
  vps_secret_set CODER_ADMIN_PASSWORD "$ADMIN_PASSWORD"
fi
vps_secret_set CODER_ADMIN_EMAIL "$ADMIN_EMAIL"
vps_secret_set CODER_ADMIN_USERNAME "$ADMIN_USER"
bootstrap_coder "$ADMIN_EMAIL" "$ADMIN_USER" "$ADMIN_PASSWORD"

ok "Coder installed: ${ACCESS_URL} (via Traefik). Admin ${ADMIN_EMAIL}; password saved to ${VPS_SECRETS_FILE}."
}

down() {
  command_exists kubectl || { zz-log w "[vps-setup] kubectl not found; nothing to remove."; return; }
  zz-log w "[vps-setup] Removing the coder namespace also deletes the PostgreSQL volume: all Coder data is lost."
  helm_teardown "$CODER_NAMESPACE" coder
  vps_secret_unset CODER_DB_PASSWORD
  vps_secret_unset CODER_ADMIN_PASSWORD
  vps_secret_unset CODER_ADMIN_EMAIL
  vps_secret_unset CODER_ADMIN_USERNAME
  ok "Coder removed."
}

summary() {
  # Opt-in step: say nothing on a host that never installed it.
  command_exists kubectl && kubectl get namespace "$CODER_NAMESPACE" >/dev/null 2>&1 || return 0
  local host
  host="$(kubectl -n "$CODER_NAMESPACE" get ingress coder -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || true)"
  cat <<EOF2
 Coder:               http://${host:-<coder host>} (through Traefik on 80/443 - public)
                       user:     $(vps_secret CODER_ADMIN_EMAIL | grep . || echo 'not set - run vps-coder/run.sh')
                       password: $(vps_secret CODER_ADMIN_PASSWORD | grep . || echo 'not set - run vps-coder/run.sh')
                       (saved to ${VPS_SECRETS_FILE}; template: kubernetes-devcontainer or devcontainer)
EOF2
}

dispatch_action "$@"
