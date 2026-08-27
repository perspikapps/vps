#!/usr/bin/env bash
# Shared helpers sourced (via `zz_use perspikapps/vps/common; . common`) by
# every feature's run.sh, each living in its own top-level folder
# (<name>/package.json + run.sh). Style borrows from devcontainers/features
# common-utils: strict mode, idempotent "already done" checks,
# non-interactive apt, plain logging.

set -euo pipefail

# Colors and leveled logging are shared with tomgrv/devcontainer-features'
# common-utils via https://github.com/tomgrv/scripts (zz_colors/zz_log) -
# bootstrap zz_use (via this repo's own setup.sh, which just delegates to
# tomgrv/scripts' own) if it isn't already on PATH (it is, on every run
# after the first: zz_use installs it into a persistent bin dir). By the
# time any feature's run.sh sources this, dispatch.sh has already cloned
# the repo and confirmed we're root, so network + write access are both
# already given.
command -v zz_use >/dev/null 2>&1 || curl -fsSL "${VPS_SETUP_URL:-https://raw.githubusercontent.com/perspikapps/vps/main/setup.sh}" | sh
zz_use zz_colors zz_log
# shellcheck disable=SC1091
. zz_colors

log()  { zz_log i "[vps-setup] $*"; }
ok()   { zz_log s "[vps-setup] $*"; }
warn() { zz_log w "[vps-setup] $*"; }
die()  { zz_log e "[vps-setup] $*"; exit 1; }

# Under `set -e`, an unguarded command failing (anything not part of an
# if/while/&&/||) kills the script immediately with only whatever *that
# command's* own stderr happened to print - which can be nothing (a
# transient network blip, a command that fails silently). Without this,
# that looks exactly like "the script just stopped with no message".
# This trap prints the failing command, file, and line before bash exits,
# so every script sourcing common.sh gets this diagnostic for free.
_vps_setup_on_error() {
  local exit_code=$?
  zz_log e "[vps-setup] ERROR: command failed (exit ${exit_code}) at ${BASH_SOURCE[1]:-$0} line ${BASH_LINENO[0]:-?}: ${BASH_COMMAND}"
}
trap _vps_setup_on_error ERR

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "This script must be run as root (use sudo)."
  fi
}

require_ubuntu() {
  [[ -r /etc/os-release ]] || die "Cannot detect OS: /etc/os-release missing."
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" ]]; then
    die "This script targets Ubuntu only (detected: ${ID:-unknown})."
  fi
  log "Detected Ubuntu ${VERSION_ID:-unknown}."
}

export DEBIAN_FRONTEND=noninteractive

apt_install() {
  apt-get install -y --no-install-recommends "$@"
}

apt_update_once() {
  if [[ -z "${VPS_SETUP_APT_UPDATED:-}" ]]; then
    log "Running apt-get update..."
    apt-get update -y
    export VPS_SETUP_APT_UPDATED=1
  fi
}

# Retry a command a few times with backoff (network installs can flake).
retry() {
  local attempts=5 delay=3 n=1
  until "$@"; do
    if (( n >= attempts )); then
      die "Command failed after ${attempts} attempts: $*"
    fi
    warn "Command failed (attempt ${n}/${attempts}), retrying in ${delay}s: $*"
    sleep "$delay"
    (( n++ ))
    (( delay *= 2 ))
  done
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Repo root, computed from this file's own location so it resolves
# correctly whether a script runs via dispatch.sh (from /opt/vps-setup) or
# standalone from a checkout elsewhere.
VPS_SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Every port this repo opens - and whether it's public or Tailscale-only -
# lives under its owning feature's own package.json, in a "vps.ports"
# array (see any of */package.json for the shape). There's no
# longer a single network.yaml: each feature owns the ports it binds.

# Resolve a feature's package.json from its short name (e.g. "cockpit" ->
# cockpit/package.json), by matching package.json's "name"
# field ("@tomgrv/vps-cockpit"). Used by net_port/net_access when a caller needs
# another feature's ports (see summary/run.sh); every other caller omits
# the second argument and gets its own package.json for free (below).
feature_package_json() {
  local feature="$1" d
  for d in "$VPS_SETUP_ROOT"/*/; do
    if [[ -f "${d}package.json" ]] && jq -e --arg n "@tomgrv/vps-${feature}" '.name == $n' "${d}package.json" >/dev/null 2>&1; then
      printf '%s' "${d}package.json"
      return 0
    fi
  done
  die "Unknown feature '${feature}' (no */package.json with name @tomgrv/vps-${feature})."
}

# Look up a port/access value from a feature's package.json ("vps.ports"),
# by its `name` field. With no $2, resolves the *calling script's own*
# package.json (<name>/package.json, right next to run.sh) -
# pass a feature name explicitly only when looking up another feature's
# port (e.g. summary/run.sh reading cockpit's port from outside cockpit's
# own run.sh). Every caller should still layer its own env var override on
# top, e.g.:
#   RANCHER_HTTP_PORT="${RANCHER_HTTP_PORT:-$(net_port rancher_http)}"
net_port() {
  local name="$1" feature="${2:-}" pkg
  if [[ -n "$feature" ]]; then
    pkg="$(feature_package_json "$feature")"
  else
    pkg="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)/package.json"
  fi
  jq -r --arg name "$name" '(.vps.ports // [])[] | select(.name == $name) | .port' "$pkg"
}

net_access() {
  local name="$1" feature="${2:-}" pkg
  if [[ -n "$feature" ]]; then
    pkg="$(feature_package_json "$feature")"
  else
    pkg="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)/package.json"
  fi
  jq -r --arg name "$name" '(.vps.ports // [])[] | select(.name == $name) | .access' "$pkg"
}

# Every port across every feature, as name/port/access/note TSV rows -
# used by security/run.sh to build ufw's rules generically,
# without needing to know which feature owns which port.
all_network_ports() {
  local f
  for f in "$VPS_SETUP_ROOT"/*/package.json; do
    jq -r '(.vps.ports // [])[] | [.name, .port, .access, (.note // "")] | @tsv' "$f"
  done
}

# Generate a random alphanumeric string of the given length (default 24).
# The `|| true` matters: `head -c N` closes its end of the pipe once it has
# read enough bytes, which sends SIGPIPE to `tr` - under `set -o pipefail`
# (which every script has via `set -euo pipefail`) that SIGPIPE (exit 141)
# becomes the pipeline's reported exit status even though `head` succeeded
# and the output is exactly right, killing the script under `set -e`.
random_password() {
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${1:-24}" || true
}

# Idempotent line-in-file helper (append only if not already present).
ensure_line() {
  local line="$1" file="$2"
  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

# Install cert-manager if it isn't already on the cluster, and reuse it
# as-is if it is - shared by rancher/run.sh and epinio/run.sh,
# whichever of the two runs first (order doesn't matter; the other then
# just reuses this same installation). Respects CERT_MANAGER_VERSION.
ensure_cert_manager() {
  if kubectl get deploy -n cert-manager cert-manager >/dev/null 2>&1; then
    log "cert-manager already installed."
    return
  fi
  log "Installing cert-manager..."
  helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
  helm repo update >/dev/null
  kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
  local version_arg=()
  [[ -n "${CERT_MANAGER_VERSION:-}" ]] && version_arg=(--version "$CERT_MANAGER_VERSION")
  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --set crds.enabled=true \
    "${version_arg[@]}" \
    --wait --timeout 5m
}

# Generic up/down dispatcher for every */run.sh. Each script defines an
# up() function (its existing install logic) and, where meaningful, a
# down() function (teardown), then finishes with:
#   dispatch_action "$@"
# Defaults to "up" so `bash <name>/run.sh` with no argument behaves
# exactly as it did before up/down actions existed.
dispatch_action() {
  local action="${1:-up}"
  case "$action" in
    up)
      up
      ;;
    down)
      if declare -f down >/dev/null; then
        down
      else
        die "This step has no 'down' action (nothing to undo)."
      fi
      ;;
    *)
      die "Unknown action '${action}' (expected 'up' or 'down')."
      ;;
  esac
}

# Uninstall a Helm release and delete its namespace, if present - shared
# teardown for every script that installs via Helm into its own namespace.
# Safe to call even if the release/namespace is already gone.
helm_teardown() {
  local namespace="$1" release="$2"
  if helm status "$release" -n "$namespace" >/dev/null 2>&1; then
    log "Uninstalling Helm release ${release} (namespace ${namespace})..."
    helm uninstall "$release" -n "$namespace" --wait || warn "helm uninstall ${release} timed out or failed."
  else
    warn "Helm release ${release} not found in namespace ${namespace}; nothing to uninstall."
  fi
  kubectl delete namespace "$namespace" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

# Rebind a Helm chart's named Service port to a different port number.
# k3s's built-in ServiceLB (Klipper) binds host ports to whatever a
# LoadBalancer Service's `port` field says, so exposing a chart's app on a
# specific host port (instead of the chart's own default) means patching
# the Service after install - this is that patch, shared by every script
# that installs a Helm chart and wants it on a non-default port.
patch_service_port() {
  local namespace="$1" service="$2" port_name="$3" new_port="$4"
  local idx
  idx="$(kubectl -n "$namespace" get service "$service" -o json | jq ".spec.ports | map(.name) | index(\"${port_name}\")")"
  if [[ "$idx" == "null" ]]; then
    warn "Service ${service} in ${namespace} has no port named '${port_name}'; leaving its ports unchanged."
    return 1
  fi
  kubectl -n "$namespace" patch service "$service" --type=json \
    -p "[{\"op\":\"replace\",\"path\":\"/spec/ports/${idx}/port\",\"value\":${new_port}}]"
}
