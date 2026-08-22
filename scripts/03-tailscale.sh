#!/usr/bin/env bash
# Install Tailscale and join the tailnet if an auth key is provided.
#
# Env vars:
#   TAILSCALE_AUTHKEY   - auth key to auto-join a tailnet (optional; if unset
#                         you'll need to run `tailscale up` interactively)
#   TAILSCALE_EXTRA_ARGS - extra flags appended to `tailscale up` (optional)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

require_root

if command_exists tailscale; then
  log "Tailscale already installed ($(tailscale --version | head -n1))."
else
  log "Installing Tailscale from the official repo..."
  retry curl -fsSL https://tailscale.com/install.sh -o /tmp/tailscale-install.sh
  bash /tmp/tailscale-install.sh
  rm -f /tmp/tailscale-install.sh
fi

systemctl enable --now tailscaled

if [[ -n "${TAILSCALE_AUTHKEY:-}" ]]; then
  log "Joining tailnet..."
  # shellcheck disable=SC2086
  tailscale up --authkey="${TAILSCALE_AUTHKEY}" --ssh ${TAILSCALE_EXTRA_ARGS:-}
  ok "Tailscale is up: $(tailscale ip -4 2>/dev/null || echo 'pending')"
else
  warn "TAILSCALE_AUTHKEY not set. Run 'tailscale up' manually to join a tailnet and authenticate."
fi
