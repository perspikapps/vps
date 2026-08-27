#!/usr/bin/env bash
# Shared helpers sourced via `zz_use perspikapps/vps/common; . common`.

set -euo pipefail

zz_use zz_colors zz_log
# shellcheck disable=SC1091
. zz_colors

ok() { zz_log s "[vps-setup] $*"; }

# Prints the failing command/file/line before exiting on any unguarded
# failure under set -e (which otherwise fails silently).
_vps_setup_on_error() {
  local exit_code=$?
  zz_log e "[vps-setup] ERROR: command failed (exit ${exit_code}) at ${BASH_SOURCE[1]:-$0} line ${BASH_LINENO[0]:-?}: ${BASH_COMMAND}"
}
trap _vps_setup_on_error ERR

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    zz_log e "[vps-setup] This script must be run as root (use sudo)."
    exit 1
  fi
}

require_ubuntu() {
  if [[ ! -r /etc/os-release ]]; then
    zz_log e "[vps-setup] Cannot detect OS: /etc/os-release missing."
    exit 1
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" ]]; then
    zz_log e "[vps-setup] This script targets Ubuntu only (detected: ${ID:-unknown})."
    exit 1
  fi
  zz_log i "[vps-setup] Detected Ubuntu ${VERSION_ID:-unknown}."
}

export DEBIAN_FRONTEND=noninteractive

apt_install() {
  apt-get install -y --no-install-recommends "$@"
}

apt_update_once() {
  if [[ -z "${VPS_SETUP_APT_UPDATED:-}" ]]; then
    zz_log i "[vps-setup] Running apt-get update..."
    apt-get update -y
    export VPS_SETUP_APT_UPDATED=1
  fi
}

retry() {
  local attempts=5 delay=3 n=1
  until "$@"; do
    if (( n >= attempts )); then
      zz_log e "[vps-setup] Command failed after ${attempts} attempts: $*"
      exit 1
    fi
    zz_log w "[vps-setup] Command failed (attempt ${n}/${attempts}), retrying in ${delay}s: $*"
    sleep "$delay"
    (( n++ ))
    (( delay *= 2 ))
  done
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Caller's location, not this file's own - zz_use always reinstalls
# common/run.sh under its own bin dir rather than reusing a checkout.
VPS_SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")/.." && pwd)"

feature_package_json() {
  local feature="$1" d
  for d in "$VPS_SETUP_ROOT"/*/; do
    if [[ -f "${d}package.json" ]] && jq -e --arg n "@tomgrv/vps-${feature}" '.name == $n' "${d}package.json" >/dev/null 2>&1; then
      printf '%s' "${d}package.json"
      return 0
    fi
  done
  zz_log e "[vps-setup] Unknown feature '${feature}' (no */package.json with name @tomgrv/vps-${feature})."
  exit 1
}

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

all_network_ports() {
  local f
  for f in "$VPS_SETUP_ROOT"/*/package.json; do
    jq -r '(.vps.ports // [])[] | [.name, .port, .access, (.note // "")] | @tsv' "$f"
  done
}

# || true: head closing early sends tr a SIGPIPE that set -o pipefail
# would otherwise report as failure despite correct output.
random_password() {
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${1:-24}" || true
}

ensure_line() {
  local line="$1" file="$2"
  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

ensure_cert_manager() {
  if kubectl get deploy -n cert-manager cert-manager >/dev/null 2>&1; then
    zz_log i "[vps-setup] cert-manager already installed."
    return
  fi
  zz_log i "[vps-setup] Installing cert-manager..."
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
        zz_log e "[vps-setup] This step has no 'down' action (nothing to undo)."
        exit 1
      fi
      ;;
    *)
      zz_log e "[vps-setup] Unknown action '${action}' (expected 'up' or 'down')."
      exit 1
      ;;
  esac
}

helm_teardown() {
  local namespace="$1" release="$2"
  if helm status "$release" -n "$namespace" >/dev/null 2>&1; then
    zz_log i "[vps-setup] Uninstalling Helm release ${release} (namespace ${namespace})..."
    helm uninstall "$release" -n "$namespace" --wait || zz_log w "[vps-setup] helm uninstall ${release} timed out or failed."
  else
    zz_log w "[vps-setup] Helm release ${release} not found in namespace ${namespace}; nothing to uninstall."
  fi
  kubectl delete namespace "$namespace" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

patch_service_port() {
  local namespace="$1" service="$2" port_name="$3" new_port="$4"
  local idx
  idx="$(kubectl -n "$namespace" get service "$service" -o json | jq ".spec.ports | map(.name) | index(\"${port_name}\")")"
  if [[ "$idx" == "null" ]]; then
    zz_log w "[vps-setup] Service ${service} in ${namespace} has no port named '${port_name}'; leaving its ports unchanged."
    return 1
  fi
  kubectl -n "$namespace" patch service "$service" --type=json \
    -p "[{\"op\":\"replace\",\"path\":\"/spec/ports/${idx}/port\",\"value\":${new_port}}]"
}
