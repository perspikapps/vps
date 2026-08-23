#!/usr/bin/env bash
# Install Tailscale, join the tailnet, and make sure tailscaled runs as a
# systemd service. If authenticated, also exposes a small placeholder
# webserver on TAILSCALE_SERVE_PORT (default 8052) via `tailscale serve`
# (tailnet-only, HTTPS) and, unless disabled, `tailscale funnel` (public
# internet too, via Tailscale's edge - no inbound ufw port needed for
# either path, both ride over tailscaled's own networking).
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
#   TAILSCALE_SERVE_PORT  - port to serve/funnel (default: 8052)
#   TAILSCALE_ENABLE_FUNNEL - "true" (default) to also expose
#                           TAILSCALE_SERVE_PORT to the public internet via
#                           Tailscale Funnel, not just the tailnet. Note:
#                           Funnel has historically only supported ports
#                           443, 8443, and 10000 on some Tailscale/tailnet
#                           configurations - if enabling it on a different
#                           port is rejected, check `tailscale funnel status`
#                           and https://tailscale.com/kb/1223/funnel.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

require_root

TAILSCALE_SERVE_PORT="${TAILSCALE_SERVE_PORT:-8052}"
TAILSCALE_ENABLE_FUNNEL="${TAILSCALE_ENABLE_FUNNEL:-true}"

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

# A minimal local backend for `tailscale serve` to proxy - bound to
# 127.0.0.1 only, never reachable except through Tailscale's own proxy.
log "Setting up a placeholder webserver on 127.0.0.1:${TAILSCALE_SERVE_PORT}..."
install -d -m 755 /var/www/vps-placeholder
cat > /var/www/vps-placeholder/index.html <<EOF
<!doctype html>
<html><body>
<h1>vps-setup placeholder</h1>
<p>Reachable via Tailscale on port ${TAILSCALE_SERVE_PORT}. Replace
/var/www/vps-placeholder with your own app, or point
vps-webserver.service at a different port/directory.</p>
</body></html>
EOF

cat > /etc/systemd/system/vps-webserver.service <<EOF
[Unit]
Description=vps-setup placeholder webserver (proxied by tailscale serve)
After=network.target

[Service]
ExecStart=/usr/bin/python3 -m http.server ${TAILSCALE_SERVE_PORT} --bind 127.0.0.1 --directory /var/www/vps-placeholder
Restart=on-failure
DynamicUser=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now vps-webserver.service
ok "vps-webserver.service running on 127.0.0.1:${TAILSCALE_SERVE_PORT}."

log "Serving port ${TAILSCALE_SERVE_PORT} to the tailnet over HTTPS..."
tailscale serve --bg --https="${TAILSCALE_SERVE_PORT}" "http://127.0.0.1:${TAILSCALE_SERVE_PORT}"
# tailscale serve's HTTPS cert is issued for the tailnet MagicDNS name, not
# the node's bare IP, so show that name here rather than `tailscale ip`.
TAILSCALE_DNSNAME=""
if command_exists jq; then
  TAILSCALE_DNSNAME="$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty' | sed 's/\.$//' || true)"
fi
ok "tailscale serve is up: https://${TAILSCALE_DNSNAME:-<magicdns-name>}:${TAILSCALE_SERVE_PORT}"

if [[ "$TAILSCALE_ENABLE_FUNNEL" == "true" ]]; then
  log "Enabling Tailscale Funnel to expose port ${TAILSCALE_SERVE_PORT} to the public internet..."
  if tailscale funnel "${TAILSCALE_SERVE_PORT}" on; then
    ok "Funnel is on for port ${TAILSCALE_SERVE_PORT} - check 'tailscale funnel status' for the public URL."
  else
    warn "Could not enable Funnel on port ${TAILSCALE_SERVE_PORT}. Funnel has historically only" \
         "supported ports 443, 8443, and 10000 on some tailnets, and needs HTTPS certs + Funnel" \
         "enabled for this node in the admin console: https://tailscale.com/kb/1223/funnel. The" \
         "tailnet-only 'tailscale serve' above is unaffected."
  fi
else
  log "TAILSCALE_ENABLE_FUNNEL=false: port ${TAILSCALE_SERVE_PORT} stays tailnet-only (not public)."
fi
