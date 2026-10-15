#!/usr/bin/env bash
# Shared helpers sourced via `zz-use perspikapps/vps/vps-common; . vps-common`.

set -euo pipefail

zz-use zz-colors zz-log
# shellcheck disable=SC1091
. zz-colors

ok() { zz-log s "[vps-setup] $*"; }

# Prints the failing command/file/line before exiting on any unguarded
# failure under set -e (which otherwise fails silently).
_vps_setup_on_error() {
  local exit_code=$?
  zz-log e "[vps-setup] ERROR: command failed (exit ${exit_code}) at ${BASH_SOURCE[1]:-$0} line ${BASH_LINENO[0]:-?}: ${BASH_COMMAND}"
}
trap _vps_setup_on_error ERR

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    zz-log e "[vps-setup] This script must be run as root (use sudo)."
    exit 1
  fi
}

require_ubuntu() {
  if [[ ! -r /etc/os-release ]]; then
    zz-log e "[vps-setup] Cannot detect OS: /etc/os-release missing."
    exit 1
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" ]]; then
    zz-log e "[vps-setup] This script targets Ubuntu only (detected: ${ID:-unknown})."
    exit 1
  fi
  zz-log i "[vps-setup] Detected Ubuntu ${VERSION_ID:-unknown}."
}

export DEBIAN_FRONTEND=noninteractive

apt_install() {
  apt-get install -y --no-install-recommends "$@"
}

apt_update_once() {
  if [[ -z "${VPS_SETUP_APT_UPDATED:-}" ]]; then
    zz-log i "[vps-setup] Running apt-get update..."
    apt-get update -y
    export VPS_SETUP_APT_UPDATED=1
  fi
}

retry() {
  local attempts=5 delay=3 n=1
  until "$@"; do
    if (( n >= attempts )); then
      zz-log e "[vps-setup] Command failed after ${attempts} attempts: $*"
      exit 1
    fi
    zz-log w "[vps-setup] Command failed (attempt ${n}/${attempts}), retrying in ${delay}s: $*"
    sleep "$delay"
    (( n++ ))
    (( delay *= 2 ))
  done
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Caller's location, not this file's own - zz-use always reinstalls
# vps-common/run.sh under its own bin dir rather than reusing a checkout.
VPS_SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")/.." && pwd)"

# Real feature folders: run.sh alongside package.json. Skips node_modules/*
# (and any other non-feature directory) instead of jq-parsing every
# package.json under the checkout.
feature_dirs() {
  local d
  for d in "$VPS_SETUP_ROOT"/*/; do
    if [[ -f "${d}run.sh" ]] && [[ -f "${d}package.json" ]]; then
      printf '%s\n' "${d%/}"
    fi
  done
}

feature_package_json() {
  local feature="$1" d
  while IFS= read -r d; do
    if jq -e --arg n "@tomgrv/${feature}" '.name == $n' "${d}/package.json" >/dev/null 2>&1; then
      printf '%s' "${d}/package.json"
      return 0
    fi
  done < <(feature_dirs)
  zz-log e "[vps-setup] Unknown feature '${feature}' (no */package.json with name @tomgrv/${feature})."
  exit 1
}

# Feature folders that are installable steps (have a "vps" key), in vps.order.
ordered_feature_dirs() {
  local d
  while IFS= read -r d; do
    jq -r --arg d "$d" 'select(.vps != null) | [(.vps.order // 999), $d] | @tsv' "${d}/package.json"
  done < <(feature_dirs) | sort -n | cut -f2
}

# Port <name> of <feature> (default: the calling step's own package.json). An
# environment variable named after the port (cockpit_http -> COCKPIT_HTTP_PORT)
# overrides the package.json default, for every caller alike.
net_port() {
  local name="$1" feature="${2:-}" pkg override
  override="${name^^}_PORT"
  if [[ -n "${!override:-}" ]]; then
    printf '%s\n' "${!override}"
    return 0
  fi
  if [[ -n "$feature" ]]; then
    pkg="$(feature_package_json "$feature")"
  else
    pkg="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)/package.json"
  fi
  jq -r --arg name "$name" '(.vps.ports // [])[] | select(.name == $name) | .port' "$pkg"
}

# Every feature's ports as TSV (name, port, access, note); the port honours
# the same environment override as net_port.
all_network_ports() {
  local d name port access note override
  while IFS= read -r d; do
    while IFS=$'\t' read -r name port access note; do
      override="${name^^}_PORT"
      printf '%s\t%s\t%s\t%s\n' "$name" "${!override:-$port}" "$access" "$note"
    done < <(jq -r '(.vps.ports // [])[] | [.name, .port, .access, (.note // "")] | @tsv' "${d}/package.json")
  done < <(feature_dirs)
}

# Private access: ports with access "private" are only reachable over one
# interface. Whoever provides that network says so by persisting
# VPS_PRIVATE_INTERFACE (vps-tailscale does on install, to the file below);
# a caller can also just set it (wg0, a LAN NIC...). The environment wins.
VPS_PRIVATE_ACCESS_FILE="${VPS_PRIVATE_ACCESS_FILE:-/etc/vps-private-access.env}"

private_interface() {
  if [[ -n "${VPS_PRIVATE_INTERFACE:-}" ]]; then
    printf '%s' "$VPS_PRIVATE_INTERFACE"
  elif [[ -f "$VPS_PRIVATE_ACCESS_FILE" ]]; then
    sed -n 's/^VPS_PRIVATE_INTERFACE=//p' "$VPS_PRIVATE_ACCESS_FILE" | tail -n1
  fi
}

# First IPv4 address of the private interface (empty when it has none yet).
private_address() {
  local iface
  iface="$(private_interface)"
  [[ -z "$iface" ]] || ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true
}

# Host for the URLs a step's summary prints: the private address, if any.
summary_host() {
  local ip
  ip="$(private_address)"
  printf '%s' "${ip:-<private-ip>}"
}

# Fetch an installer script and run it with <shell> (default sh), via a
# private temp file instead of a predictable /tmp path.
download_run() {
  local url="$1" shell="${2:-sh}" f rc=0
  f="$(mktemp)"
  retry curl -fsSL "$url" -o "$f"
  "$shell" "$f" || rc=$?
  rm -f "$f"
  return "$rc"
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

# One status line for a namespace: elapsed time, pods ready/total, and what the
# others are doing (ContainerCreating, ImagePullBackOff...).
progress_line() {
  local ns="$1" label="$2" elapsed="$3" pods ready total waiting
  pods="$(kubectl -n "$ns" get pods --no-headers 2>/dev/null || true)"
  if [[ -z "$pods" ]]; then
    zz-log i "[vps-setup] ${label}: ${elapsed}s, no pod in ${ns} yet (chart and images are still being fetched)..."
    return
  fi
  total="$(printf '%s\n' "$pods" | grep -c .)"
  ready="$(printf '%s\n' "$pods" | awk '$3 == "Completed" || ($3 == "Running" && split($2, a, "/") && a[1] == a[2]) { n++ } END { print n + 0 }')"
  waiting="$(printf '%s\n' "$pods" | awk '$3 != "Completed" && !($3 == "Running" && split($2, a, "/") && a[1] == a[2]) { printf "%s=%s ", $1, $3 }')"
  zz-log i "[vps-setup] ${label}: ${elapsed}s, ${ready}/${total} pods ready${waiting:+ - waiting: ${waiting}}"
}

# run_with_progress <namespace> <label> <command...>: runs the command as is
# (its output and exit status untouched) and, while it works, logs a status
# line every PROGRESS_INTERVAL seconds (default 15), so a long `helm --wait`
# or `kubectl rollout status` does not look frozen.
run_with_progress() {
  local ns="$1" label="$2" parent=$$ start=$SECONDS watcher rc=0
  shift 2
  (
    while sleep "${PROGRESS_INTERVAL:-15}"; do
      kill -0 "$parent" 2>/dev/null || exit 0
      progress_line "$ns" "$label" "$((SECONDS - start))"
    done
  ) &
  watcher=$!
  "$@" || rc=$?
  kill "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  return "$rc"
}

# What is stuck in a namespace, for a failed wait: pods and services, recent
# events, the k3s ServiceLB pods (a LoadBalancer Service whose host ports are
# taken stays pending there) and why each unready pod is not running.
dump_diagnostics() {
  local ns="$1" pod
  zz-log w "[vps-setup] --- diagnostics for namespace ${ns} ---"
  kubectl -n "$ns" get pods,svc -o wide 2>&1 || true
  kubectl -n "$ns" get events --sort-by=.lastTimestamp 2>&1 | tail -n 15 || true
  kubectl -n kube-system get pods -o wide 2>&1 | grep -E 'NAME|svclb' || true
  for pod in $(kubectl -n "$ns" get pods --no-headers 2>/dev/null | awk '$3 != "Running" && $3 != "Completed" {print $1}'); do
    kubectl -n "$ns" describe pod "$pod" 2>&1 | sed -n '/^Events:/,$p' | tail -n 8 || true
  done
  for pod in $(kubectl -n kube-system get pods --no-headers 2>/dev/null | awk '/svclb/ && $3 != "Running" {print $1}'); do
    kubectl -n kube-system describe pod "$pod" 2>&1 | sed -n '/^Events:/,$p' | tail -n 4 || true
  done
  zz-log w "[vps-setup] --- end of diagnostics ---"
}

ensure_cert_manager() {
  if kubectl get deploy -n cert-manager cert-manager >/dev/null 2>&1; then
    zz-log i "[vps-setup] cert-manager already installed."
    return
  fi
  zz-log i "[vps-setup] Installing cert-manager..."
  helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
  helm repo update >/dev/null
  kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
  local version_arg=()
  [[ -n "${CERT_MANAGER_VERSION:-}" ]] && version_arg=(--version "$CERT_MANAGER_VERSION")
  run_with_progress cert-manager "cert-manager install" \
    helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --set crds.enabled=true \
    "${version_arg[@]}" \
    --wait --timeout 5m
}

# Runs the step's up(), down() or summary(); root is required for the first two.
# A step without summary() has nothing to report.
dispatch_action() {
  local action="${1:-up}"
  case "$action" in
    up)
      require_root
      up
      ;;
    down)
      require_root
      if declare -f down >/dev/null; then
        down
      else
        zz-log e "[vps-setup] This step has no 'down' action (nothing to undo)."
        exit 1
      fi
      ;;
    summary)
      if declare -f summary >/dev/null; then summary; fi
      ;;
    *)
      zz-log e "[vps-setup] Unknown action '${action}' (expected 'up', 'down' or 'summary')."
      exit 1
      ;;
  esac
}

helm_teardown() {
  local namespace="$1" release="$2"
  if helm status "$release" -n "$namespace" >/dev/null 2>&1; then
    zz-log i "[vps-setup] Uninstalling Helm release ${release} (namespace ${namespace})..."
    helm uninstall "$release" -n "$namespace" --wait || zz-log w "[vps-setup] helm uninstall ${release} timed out or failed."
  else
    zz-log w "[vps-setup] Helm release ${release} not found in namespace ${namespace}; nothing to uninstall."
  fi
  kubectl delete namespace "$namespace" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

patch_service_port() {
  local namespace="$1" service="$2" port_name="$3" new_port="$4"
  local idx
  idx="$(kubectl -n "$namespace" get service "$service" -o json | jq ".spec.ports | map(.name) | index(\"${port_name}\")")"
  if [[ "$idx" == "null" ]]; then
    zz-log w "[vps-setup] Service ${service} in ${namespace} has no port named '${port_name}'; leaving its ports unchanged."
    return 1
  fi
  kubectl -n "$namespace" patch service "$service" --type=json \
    -p "[{\"op\":\"replace\",\"path\":\"/spec/ports/${idx}/port\",\"value\":${new_port}}]"
}
