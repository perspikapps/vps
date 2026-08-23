#!/usr/bin/env bash
# Install Tailscale, join the tailnet, and make sure tailscaled runs as a
# systemd service.
#
# setup.sh refuses to run at all if this step is enabled but
# TAILSCALE_AUTHKEY is unset, since ufw only opens Cockpit/Rancher/k3s to
# the tailscale0 interface - an unauthenticated node would leave all of
# them unreachable. Pass --skip-tailscale there to opt out of that guard.
#
# Env vars:
#   TAILSCALE_AUTHKEY     - auth key to auto-join a tailnet (required unless
#                           this step is skipped - see setup.sh's guard)
#   TAILSCALE_EXTRA_ARGS  - extra flags appended to `tailscale up` (optional)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

require_root

if command_exists tailscale; then
  log "Tailscale already installed ($(tailscale --version | head -n1 || true))."
else
  log "Installing Tailscale from the official repo..."
  retry curl -fsSL https://tailscale.com/install.sh -o /tmp/tailscale-install.sh
  bash /tmp/tailscale-install.sh
  rm -f /tmp/tailscale-install.sh
fi

log "Enabling tailscaled as a systemd service..."
systemctl enable --now tailscaled
systemctl is-active --quiet tailscaled || die "tailscaled is not active after 'systemctl enable --now tailscaled'."
ok "tailscaled is running as a service ($(systemctl is-enabled tailscaled))."

if [[ -z "${TAILSCALE_AUTHKEY:-}" ]]; then
  warn "TAILSCALE_AUTHKEY not set. Run 'tailscale up' manually to join a tailnet and authenticate, then re-run: sudo bash setup.sh --only-tailscale"
  exit 0
fi

log "Joining tailnet..."
# shellcheck disable=SC2086
tailscale up --authkey="${TAILSCALE_AUTHKEY}" --ssh ${TAILSCALE_EXTRA_ARGS:-}
ok "Tailscale is up: $(tailscale ip -4 2>/dev/null || echo 'pending')"
