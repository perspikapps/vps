#!/usr/bin/env bash
# Install Tailscale, join the tailnet, and make sure tailscaled runs as a
# systemd service.
#
# dispatch.sh refuses to run at all if this step is enabled but
# TAILSCALE_AUTHKEY is unset, since ufw only opens this repo's
# Tailscale-only services (see network.yaml) to the tailscale0 interface -
# an unauthenticated node would leave all of them unreachable. Pass
# --skip-tailscale there to opt out of that guard.
#
# Env vars:
#   TAILSCALE_AUTHKEY     - auth key to auto-join a tailnet (required unless
#                           this step is skipped - see dispatch.sh's guard)
#   TAILSCALE_EXTRA_ARGS  - extra flags appended to `tailscale up` (optional)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../lib/common.sh"

up() {
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
  warn "TAILSCALE_AUTHKEY not set. Run 'tailscale up' manually to join a tailnet and authenticate, then re-run: sudo sh dispatch.sh --only-tailscale"
  exit 0
fi

log "Joining tailnet..."
# shellcheck disable=SC2086
tailscale up --authkey="${TAILSCALE_AUTHKEY}" --ssh ${TAILSCALE_EXTRA_ARGS:-}
ok "Tailscale is up: $(tailscale ip -4 2>/dev/null || echo 'pending')"
}

# Logs out of the tailnet and stops tailscaled, but leaves the tailscale
# package installed (it's a single small binary; PURGE_TAILSCALE=true also
# removes it). Note: every Tailscale-only service in network.yaml becomes
# unreachable once this runs - see README's Security model.
down() {
  require_root
  if ! command_exists tailscale; then
    warn "Tailscale not installed; nothing to do."
    return
  fi
  log "Logging out of the tailnet..."
  tailscale logout || true
  systemctl disable --now tailscaled || true
  if [[ "${PURGE_TAILSCALE:-false}" == "true" ]]; then
    log "Purging the tailscale package (PURGE_TAILSCALE=true)..."
    apt-get purge -y tailscale 2>/dev/null || true
  fi
  warn "Tailscale is disconnected. Cockpit, Rancher, ArgoCD, the Traefik" \
       "dashboard, and the k3s API (all Tailscale-only) are now unreachable" \
       "until you re-run this step's 'up' action."
  ok "Tailscale brought down."
}

dispatch_action "$@"
