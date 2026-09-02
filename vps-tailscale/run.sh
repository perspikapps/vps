#!/usr/bin/env bash
# Tailscale. Env vars: see README.

set -euo pipefail
command -v zz_use >/dev/null 2>&1 || { echo "zz_use not found on PATH - run this repo's setup.sh first: curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/setup.sh | sh" >&2; exit 1; }
zz_use "perspikapps/vps/vps-common@${VPS_SETUP_REPO_REF:-main}"
# shellcheck disable=SC1091
. vps-common

up() {
require_root

if command_exists tailscale; then
  zz_log i "[vps-setup] Tailscale already installed ($(tailscale --version | head -n1 || true))."
else
  zz_log i "[vps-setup] Installing Tailscale from the official repo..."
  retry curl -fsSL https://tailscale.com/install.sh -o /tmp/tailscale-install.sh
  bash /tmp/tailscale-install.sh
  rm -f /tmp/tailscale-install.sh
fi

zz_log i "[vps-setup] Enabling tailscaled as a systemd service..."
systemctl enable --now tailscaled
systemctl is-active --quiet tailscaled || { zz_log e "[vps-setup] tailscaled is not active after 'systemctl enable --now tailscaled'."; exit 1; }
ok "tailscaled is running as a service ($(systemctl is-enabled tailscaled))."

if [[ -z "${TAILSCALE_AUTHKEY:-}" ]]; then
  zz_log w "[vps-setup] TAILSCALE_AUTHKEY not set. Run 'tailscale up' manually to join a tailnet and authenticate, then re-run: sudo sh dispatch.sh --only-tailscale"
  exit 0
fi

zz_log i "[vps-setup] Joining tailnet..."
# shellcheck disable=SC2086
tailscale up --authkey="${TAILSCALE_AUTHKEY}" --ssh ${TAILSCALE_EXTRA_ARGS:-}
ok "Tailscale is up: $(tailscale ip -4 2>/dev/null || echo 'pending')"
}

down() {
  require_root
  if ! command_exists tailscale; then
    zz_log w "[vps-setup] Tailscale not installed; nothing to do."
    return
  fi
  zz_log i "[vps-setup] Logging out of the tailnet..."
  tailscale logout || true
  systemctl disable --now tailscaled || true
  if [[ "${PURGE_TAILSCALE:-false}" == "true" ]]; then
    zz_log i "[vps-setup] Purging the tailscale package (PURGE_TAILSCALE=true)..."
    apt-get purge -y tailscale 2>/dev/null || true
  fi
  zz_log w "[vps-setup] Tailscale is disconnected. Cockpit, Rancher, the Traefik" \
       "dashboard, and the k3s API (all Tailscale-only) are now unreachable" \
       "until you re-run this step's 'up' action."
  ok "Tailscale brought down."
}

dispatch_action "$@"
