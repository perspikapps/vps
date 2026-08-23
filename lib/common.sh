#!/usr/bin/env bash
# Shared helpers sourced by every script in scripts/.
# Style borrows from devcontainers/features common-utils: strict mode,
# idempotent "already done" checks, non-interactive apt, plain logging.

set -euo pipefail

COLOR_RED=$'\033[0;31m'
COLOR_GREEN=$'\033[0;32m'
COLOR_YELLOW=$'\033[0;33m'
COLOR_BLUE=$'\033[0;34m'
COLOR_RESET=$'\033[0m'

log()  { printf '%s[vps-setup]%s %s\n' "$COLOR_BLUE" "$COLOR_RESET" "$*"; }
ok()   { printf '%s[vps-setup]%s %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$*"; }
warn() { printf '%s[vps-setup]%s %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$*" >&2; }
die()  { printf '%s[vps-setup]%s %s\n' "$COLOR_RED" "$COLOR_RESET" "$*" >&2; exit 1; }

# Under `set -e`, an unguarded command failing (anything not part of an
# if/while/&&/||) kills the script immediately with only whatever *that
# command's* own stderr happened to print - which can be nothing (a
# transient network blip, a command that fails silently). Without this,
# that looks exactly like "the script just stopped with no message".
# This trap prints the failing command, file, and line before bash exits,
# so every script sourcing common.sh gets this diagnostic for free.
_vps_setup_on_error() {
  local exit_code=$?
  printf '%s[vps-setup]%s ERROR: command failed (exit %s) at %s line %s: %s\n' \
    "$COLOR_RED" "$COLOR_RESET" "$exit_code" \
    "${BASH_SOURCE[1]:-$0}" "${BASH_LINENO[0]:-?}" "$BASH_COMMAND" >&2
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
