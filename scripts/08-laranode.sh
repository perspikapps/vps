#!/usr/bin/env bash
# Installs Laranode (https://laranode.com), an open-source Laravel/LAMP
# hosting control panel, via its official one-line installer. Unlike
# everything else in this repo, Laranode has no container image or Helm
# chart upstream - it's a traditional VPS panel that installs its own
# Apache/MySQL/PHP-FPM stack directly on the host and manages its own
# systemd services, so it's installed natively here rather than into k3s.
#
# Laranode's installer opens ufw for 80, 443, and 8080 (its Reverb
# websocket service) PUBLICLY - unlike the rest of this repo's
# Tailscale-only default, and left that way here on purpose: Laranode's
# whole point is hosting public-facing websites (and its "one-click Let's
# Encrypt" feature needs port 80 reachable from the public internet for
# ACME HTTP-01 validation), so restricting it to Tailscale by default
# would defeat its own core purpose. Set LARANODE_TAILSCALE_ONLY=true if
# you specifically want it private instead (e.g. an internal-only panel).
#
# NOTE: Laranode hardcodes port 8080 for Reverb, which collides with this
# repo's own RANCHER_HTTP_PORT default (also 8080) if you install both -
# set RANCHER_HTTP_PORT to something else first if so.
#
# Env vars:
#   LARANODE_TAILSCALE_ONLY - "true" to restrict Laranode's ports
#                             (80/443/8080) to Tailscale instead of
#                             leaving them public (default: false - see
#                             note above on why public is the default)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

require_root
apt_update_once

LARANODE_TAILSCALE_ONLY="${LARANODE_TAILSCALE_ONLY:-false}"

if [[ "${RANCHER_HTTP_PORT:-8080}" == "8080" ]]; then
  warn "Laranode's Reverb websocket service hardcodes port 8080, the same" \
       "as this repo's default RANCHER_HTTP_PORT. If you're installing" \
       "both, set RANCHER_HTTP_PORT to something else before running" \
       "scripts/06-rancher.sh."
fi

if systemctl list-unit-files 2>/dev/null | grep -q '^laranode'; then
  log "Laranode already installed (laranode systemd units present); skipping installer."
  log "Re-run its installer manually to upgrade: see https://laranode.com"
else
  log "Running the official Laranode installer..."
  retry curl -fsSL https://raw.githubusercontent.com/crivion/laranode/main/laranode-scripts/bin/laranode-installer.sh -o /tmp/laranode-installer.sh
  bash /tmp/laranode-installer.sh
  rm -f /tmp/laranode-installer.sh
  ok "Laranode installer finished - credentials it printed above are shown only once, save them now."
fi

if [[ "$LARANODE_TAILSCALE_ONLY" == "true" ]]; then
  log "LARANODE_TAILSCALE_ONLY=true: restricting Laranode's ports (80/443/8080) to Tailscale..."
  warn "This also disables Laranode's own Let's Encrypt issuance (ACME" \
       "HTTP-01 needs port 80 reachable from the public internet)."
  for port in 80 443 8080; do
    ufw delete allow "${port}/tcp" >/dev/null 2>&1 || true
    ufw allow in on tailscale0 to any port "$port" proto tcp comment "vps-setup: tailscale-only (laranode)" || true
  done
  ufw reload >/dev/null 2>&1 || true
  ok "Laranode restricted to Tailscale."
else
  ok "Laranode left public on 80/443/8080 (its installer's own ufw rules), so its hosted" \
     "sites and Let's Encrypt issuance work as intended. Set LARANODE_TAILSCALE_ONLY=true" \
     "to restrict it to Tailscale instead."
fi
