#!/bin/sh
# Shared helpers sourced via `zz-use perspikapps/vps/vps-common; . vps-common`.

set -eu
# pipefail is not in every POSIX sh (dash): use it where the shell has it.
# shellcheck disable=SC3040
(set -o pipefail) 2>/dev/null && set -o pipefail

zz-use zz-colors zz-log yaml-render zz-install zz-workspaces
# shellcheck disable=SC1091
. zz-colors

ok() { zz-log s "[vps-setup] $*"; }

# Reports an unguarded failure under set -e (which otherwise fails silently).
# POSIX sh has no ERR trap, so this runs on exit; a step that logged its own
# error and then exits is reported once more with its status.
report_exit() {
    local status=$?

    [ "$status" -eq 0 ] || zz-log e "[vps-setup] ERROR: exited with status ${status} (${0})"
}
trap report_exit EXIT

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        zz-log e "[vps-setup] This script must be run as root (use sudo)."
        exit 1
    fi
}

require_ubuntu() {
    if [ ! -r /etc/os-release ]; then
        zz-log e "[vps-setup] Cannot detect OS: /etc/os-release missing."
        exit 1
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    if [ "${ID:-}" != "ubuntu" ]; then
        zz-log e "[vps-setup] This script targets Ubuntu only (detected: ${ID:-unknown})."
        exit 1
    fi
    zz-log i "[vps-setup] Detected Ubuntu ${VERSION_ID:-unknown}."
}

export DEBIAN_FRONTEND=noninteractive

# install_packages <package>...: system packages through zz-install (whichever
# package manager is there, sudo when needed; it refreshes the apt index at most
# hourly), without the recommended extras.
install_packages() {
    local package

    for package in "$@"; do
        zz-install -m "$package"
    done
}

# Best effort: the caller decides what a package that is not there means.
apt_purge() {
    apt-get purge -y "$@" 2>/dev/null
}

# Cockpit picks up new modules / socket settings on a socket restart.
cockpit_refresh() {
    systemctl try-restart cockpit.socket 2>/dev/null || true
}

# Ports published by k3s (ServiceLB) or Docker are DNAT-ed past ufw; vps-security's
# vps-private-ports-guard unit re-inserts its FORWARD rule ahead of theirs. Call
# once k3s or Docker is up (best effort: the unit exists only after vps-security).
reapply_private_guard() {
    systemctl restart vps-private-ports-guard.service 2>/dev/null || true
}

retry() {
    local attempts=5 delay=3 n=1

    until "$@"; do
        if [ "$n" -ge "$attempts" ]; then
            zz-log e "[vps-setup] Command failed after ${attempts} attempts: $*"
            exit 1
        fi
        zz-log w "[vps-setup] Command failed (attempt ${n}/${attempts}), retrying in ${delay}s: $*"
        sleep "$delay"
        n=$((n + 1))
        delay=$((delay * 2))
    done
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Value of the environment variable named $1 (empty when unset).
get_env() { eval "printf '%s' \"\${$1:-}\""; }

# Upper-cases stdin.
to_upper() { tr '[:lower:]' '[:upper:]'; }

# Caller's location ($0 is the step being run, not this file) - zz-use always
# reinstalls vps-common/run.sh under its own bin dir rather than reusing a checkout.
VPS_SETUP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Folders of this repo's installable steps (zz-workspaces: a bin file and an
# engines.zz-setup field), in config.order. Library folders (vps-common) and
# node_modules/* are left out.
feature_dirs() {
    local root tab

    root="$VPS_SETUP_ROOT"
    tab="$(printf '\037')"
    zz-workspaces "$root" | cut -d "$tab" -f3 | sed "s|^|${root}/|"
}

# Path of the package.json of feature $1 (the name without the @tomgrv/ scope).
feature_package_json() {
    local feature="$1" d

    d="$(zz-workspaces "$VPS_SETUP_ROOT" | awk -F "$(printf '\037')" -v n="$feature" '$2 == n { print $3; exit }')"
    if [ -z "$d" ]; then
        zz-log e "[vps-setup] Unknown feature '${feature}' (no installable step named ${feature})." && exit 1
    fi
    printf '%s' "${VPS_SETUP_ROOT}/${d}/package.json"
}

# Port <name> of <feature> (default: the calling step's own package.json). An
# environment variable named after the port (cockpit_http -> COCKPIT_HTTP_PORT)
# overrides the package.json default, for every caller alike.
net_port() {
    local name="$1" feature="${2:-}" pkg override value

    override="$(printf '%s' "$name" | to_upper)_PORT"
    value="$(get_env "$override")"
    if [ -n "$value" ]; then
        printf '%s\n' "$value"
        return 0
    fi
    if [ -n "$feature" ]; then
        pkg="$(feature_package_json "$feature")"
    else
        pkg="$(cd "$(dirname "$0")" && pwd)/package.json"
    fi
    jq -r --arg name "$name" '(.config.ports // [])[] | select(.name == $name) | .port' "$pkg"
}

# Every feature's ports as TSV (name, port, access, note); the port honours
# the same environment override as net_port.
all_network_ports() {
    local d name port access note override value tab

    tab="$(printf '\t')"
    while IFS= read -r d; do
        while IFS="$tab" read -r name port access note; do
            override="$(printf '%s' "$name" | to_upper)_PORT"
            value="$(get_env "$override")"
            printf '%s\t%s\t%s\t%s\n' "$name" "${value:-$port}" "$access" "$note"
        done <<EOF
$(jq -r '(.config.ports // [])[] | [.name, .port, .access, (.note // "")] | @tsv' "${d}/package.json")
EOF
    done <<EOF
$(feature_dirs)
EOF
}

# Private access: ports with access "private" are only reachable over one
# interface. Whoever provides that network says so by persisting
# VPS_PRIVATE_INTERFACE (vps-tailscale does on install, to the file below);
# a caller can also just set it (wg0, a LAN NIC...). The environment wins.
VPS_PRIVATE_ACCESS_FILE="${VPS_PRIVATE_ACCESS_FILE:-/etc/vps-private-access.env}"

private_interface() {
    if [ -n "${VPS_PRIVATE_INTERFACE:-}" ]; then
        printf '%s' "$VPS_PRIVATE_INTERFACE"
    elif [ -f "$VPS_PRIVATE_ACCESS_FILE" ]; then
        sed -n 's/^VPS_PRIVATE_INTERFACE=//p' "$VPS_PRIVATE_ACCESS_FILE" | tail -n1
    fi
}

# First IPv4 address of the private interface (empty when it has none yet).
private_address() {
    local iface

    iface="$(private_interface)"
    [ -z "$iface" ] || ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true
}

# Host for the URLs a step's summary prints: the private address, if any.
summary_host() {
    local ip

    ip="$(private_address)"
    printf '%s' "${ip:-<private-ip>}"
}

# Whether the IPv4 address on stdin is private, loopback, link-local or CGNAT.
is_private_ip() {
    grep -Eq '^(10\.|127\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|169\.254\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.)'
}

# Public IPv4 of this host: the default-route source address, or - behind NAT
# (a private address, as on some clouds) - what an external echo service sees.
public_ip() {
    local ip

    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") {print $(i + 1); exit}}' || true)"
    if [ -z "$ip" ] || printf '%s\n' "$ip" | is_private_ip; then
        ip="$(curl -fsS -m 5 https://api.ipify.org 2>/dev/null || true)"
    fi
    printf '%s' "$ip"
}

# Wildcard DNS: apps that need per-app subdomains (Coder's workspace apps) take
# one domain. vps-system persists WILDCARD_DOMAIN when it is set; the fallback
# is nip.io on the PUBLIC address (never the private/Tailscale one: the apps are
# served by the public ingress), which resolves any <a-b-c-d>.nip.io and
# *.<a-b-c-d>.nip.io to that IP with no DNS to set up.
VPS_WILDCARD_FILE="${VPS_WILDCARD_FILE:-/etc/vps-wildcard-domain.env}"

wildcard_domain() {
    local d="${WILDCARD_DOMAIN:-}" ip

    if [ -z "$d" ] && [ -f "$VPS_WILDCARD_FILE" ]; then
        d="$(sed -n 's/^WILDCARD_DOMAIN=//p' "$VPS_WILDCARD_FILE" | tail -n1)"
    fi
    if [ -z "$d" ]; then
        ip="$(public_ip)"
        [ -z "$ip" ] || d="$(printf '%s' "$ip" | tr . -).nip.io"
    fi
    printf '%s' "$d"
}

# Credentials generated or chosen by the steps (Cockpit login, Rancher bootstrap
# password) live as KEY=VALUE lines in one owner-only env file, written with
# zz-persist (-s) - a step that stores one declares `zz-use ... zz-persist`.
VPS_SECRETS_FILE="${VPS_SECRETS_FILE:-/root/.vps-secrets.env}"

# vps_secret KEY [legacy-file]: the environment wins, then the secrets file,
# then (hosts set up by an older version) the legacy one-value file.
vps_secret() {
    local key="$1" legacy="${2:-}" value

    value="$(get_env "$key")"
    if [ -z "$value" ] && [ -f "$VPS_SECRETS_FILE" ]; then
        value="$(sed -n "s/^${key}=//p" "$VPS_SECRETS_FILE" | tail -n1)"
    fi
    if [ -z "$value" ] && [ -n "$legacy" ] && [ -f "$legacy" ]; then
        value="$(cat "$legacy")"
    fi
    printf '%s' "$value"
}

# vps_secret_set KEY VALUE [legacy-file]: store it, and migrate away the legacy file.
vps_secret_set() {
    zz-persist -s -f "$VPS_SECRETS_FILE" "$1" "$2"
    [ -z "${3:-}" ] || rm -f "$3"
}

# vps_secret_unset KEY [legacy-file]
vps_secret_unset() {
    [ ! -f "$VPS_SECRETS_FILE" ] || sed -i "/^${1}=/d" "$VPS_SECRETS_FILE"
    [ -z "${2:-}" ] || rm -f "$2"
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

    grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >>"$file"
}

# One status line for a namespace: elapsed time, pods ready/total, and what the
# others are doing (ContainerCreating, ImagePullBackOff...).
progress_line() {
    local ns="$1" label="$2" elapsed="$3" pods ready total waiting

    pods="$(kubectl -n "$ns" get pods --no-headers 2>/dev/null || true)"
    if [ -z "$pods" ]; then
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
    local ns="$1" label="$2" parent=$$ start watcher rc=0

    shift 2
    start="$(date +%s)"
    (
        while sleep "${PROGRESS_INTERVAL:-15}"; do
            kill -0 "$parent" 2>/dev/null || exit 0
            progress_line "$ns" "$label" "$(($(date +%s) - start))"
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
    # shortcut: the unquoted version splits on spaces, a chart version has none.
    # shellcheck disable=SC2086
    run_with_progress cert-manager "cert-manager install" \
        helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --set crds.enabled=true \
        ${CERT_MANAGER_VERSION:+--version $CERT_MANAGER_VERSION} \
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
            if command_exists down; then
                down
            else
                zz-log e "[vps-setup] This step has no 'down' action (nothing to undo)."
                exit 1
            fi
            ;;
        summary)
            if command_exists summary; then summary; fi
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
    local namespace="$1" service="$2" port_name="$3" new_port="$4" idx

    idx="$(kubectl -n "$namespace" get service "$service" -o json | jq ".spec.ports | map(.name) | index(\"${port_name}\")")"
    if [ "$idx" = "null" ]; then
        zz-log w "[vps-setup] Service ${service} in ${namespace} has no port named '${port_name}'; leaving its ports unchanged."
        return 1
    fi
    kubectl -n "$namespace" patch service "$service" --type=json \
        -p "[{\"op\":\"replace\",\"path\":\"/spec/ports/${idx}/port\",\"value\":${new_port}}]"
}
