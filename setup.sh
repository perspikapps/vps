#!/usr/bin/env bash
#
# One-line VPS bootstrapper for a fresh Ubuntu install.
#
#   curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/setup.sh | sudo bash
#
# Clones/updates this repo into /opt/vps-setup and runs the numbered scripts
# in scripts/ in order. Each step is idempotent and can be skipped with an
# env var or CLI flag. Run with --help for options.
#
# Inspired by the modular "leading script + dependent scripts" layout of
# https://github.com/jmilinovich/vps-setup-skill and by the install
# conventions used in devcontainers/features (common-utils): strict bash
# mode, non-interactive apt, idempotent checks, plain colored logging.

set -euo pipefail

REPO_URL="${VPS_SETUP_REPO_URL:-https://github.com/perspikapps/vps.git}"
REPO_REF="${VPS_SETUP_REPO_REF:-main}"
INSTALL_DIR="${VPS_SETUP_DIR:-/opt/vps-setup}"

SKIP_SECURITY=0
SKIP_TAILSCALE=0
SKIP_COCKPIT=0
SKIP_K3S=0
SKIP_RANCHER=0

usage() {
  cat <<'EOF'
Usage: setup.sh [options]

Options:
  --skip-security     Skip firewall/SSH/fail2ban hardening (scripts/02)
  --skip-tailscale     Skip Tailscale install (scripts/03)
  --skip-cockpit        Skip Cockpit install (scripts/04)
  --skip-k3s              Skip k3s/kubectl/helm install (scripts/05)
  --skip-rancher      Skip Rancher install (scripts/06)
  -h, --help                Show this help

Environment variables (see README.md for the full list):
  TAILSCALE_AUTHKEY, RANCHER_HOSTNAME, RANCHER_BOOTSTRAP_PASSWORD,
  COCKPIT_HTTP_PORT, COCKPIT_HTTPS_PORT, RANCHER_HTTP_PORT, RANCHER_HTTPS_PORT,
  VPS_ADMIN_USER, VPS_ADMIN_SSH_KEY
EOF
}

for arg in "$@"; do
  case "$arg" in
    --skip-security) SKIP_SECURITY=1 ;;
    --skip-tailscale) SKIP_TAILSCALE=1 ;;
    --skip-cockpit) SKIP_COCKPIT=1 ;;
    --skip-k3s) SKIP_K3S=1 ;;
    --skip-rancher) SKIP_RANCHER=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage; exit 1 ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "[vps-setup] This script must be run as root (use sudo)." >&2
  exit 1
fi

echo "[vps-setup] repo=${REPO_URL} ref=${REPO_REF} dir=${INSTALL_DIR}"
if [[ -z "${VPS_SETUP_REPO_REF:-}" && "$REPO_REF" == "main" ]]; then
  echo "[vps-setup] (VPS_SETUP_REPO_REF not set - using 'main'. Note: a plain" >&2
  echo "[vps-setup]  shell 'export' before '| sudo bash' is dropped by sudo;" >&2
  echo "[vps-setup]  set it on the sudo line instead, e.g. 'sudo VPS_SETUP_REPO_REF=... bash'.)" >&2
fi

if [[ -d "$INSTALL_DIR/.git" ]]; then
  echo "[vps-setup] Updating existing checkout in $INSTALL_DIR..."
  # A one-off `fetch origin <ref>` populates FETCH_HEAD but does NOT create
  # or update a remote-tracking ref like origin/<ref> (that only happens
  # with the repo's configured fetch refspec) - so reset against FETCH_HEAD
  # directly, which works for branches, tags, and commit SHAs alike.
  git -C "$INSTALL_DIR" fetch --depth 1 origin "$REPO_REF"
  git -C "$INSTALL_DIR" checkout -q -B "$REPO_REF" FETCH_HEAD
  git -C "$INSTALL_DIR" reset --hard FETCH_HEAD
elif [[ -d "$INSTALL_DIR" ]]; then
  echo "[vps-setup] $INSTALL_DIR exists and is not a git checkout; running scripts in place."
else
  echo "[vps-setup] Cloning $REPO_URL (ref: $REPO_REF) into $INSTALL_DIR..."
  command -v git >/dev/null 2>&1 || (apt-get update -y && apt-get install -y --no-install-recommends git)
  git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# shellcheck disable=SC1091
source "$INSTALL_DIR/lib/common.sh"

require_root
require_ubuntu

run_step() {
  local script="$1" skip="$2" label="$3"
  if [[ "$skip" -eq 1 ]]; then
    warn "Skipping ${label} (${script})"
    return
  fi
  log "=== Running ${label} (${script}) ==="
  bash "$INSTALL_DIR/scripts/${script}"
  ok "=== Done: ${label} ==="
}

run_step "01-system-update.sh"     0               "Base system update & essentials"
run_step "02-security-harden.sh"   "$SKIP_SECURITY" "Firewall / SSH / fail2ban hardening"
run_step "03-tailscale.sh"         "$SKIP_TAILSCALE" "Tailscale install"
run_step "04-cockpit.sh"           "$SKIP_COCKPIT"  "Cockpit install"
run_step "05-k3s.sh"               "$SKIP_K3S"      "k3s / kubectl / helm install"
run_step "06-rancher.sh"           "$SKIP_RANCHER"  "Rancher install"
bash "$INSTALL_DIR/scripts/99-summary.sh"
