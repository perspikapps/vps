#!/usr/bin/env bash
# Print a final summary of what was installed and how to reach it.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

COCKPIT_HTTP_PORT="${COCKPIT_HTTP_PORT:-9080}"
COCKPIT_HTTPS_PORT="${COCKPIT_HTTPS_PORT:-9083}"
RANCHER_HTTP_PORT="${RANCHER_HTTP_PORT:-8080}"
RANCHER_HTTPS_PORT="${RANCHER_HTTPS_PORT:-8083}"
TAILSCALE_SERVE_PORT="${TAILSCALE_SERVE_PORT:-8052}"

TAILSCALE_IP="$(tailscale ip -4 2>/dev/null || true)"
HOST_FOR_URLS="${TAILSCALE_IP:-<tailscale-ip>}"
[[ -z "$TAILSCALE_IP" ]] && TAILSCALE_STATUS="not joined yet - run: tailscale up" || TAILSCALE_STATUS="$TAILSCALE_IP"

# tailscale serve's HTTPS cert is issued for the tailnet MagicDNS name, not
# the raw IP - Cockpit/Rancher use their own self-signed certs so the IP
# above is fine for those, but the serve/funnel URL needs the real name.
TAILSCALE_DNSNAME=""
if command_exists jq; then
  TAILSCALE_DNSNAME="$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty' | sed 's/\.$//' || true)"
fi
HOST_FOR_SERVE="${TAILSCALE_DNSNAME:-$HOST_FOR_URLS}"

COCKPIT_USER="$(cat /root/.cockpit-admin-user 2>/dev/null || echo 'not set - run scripts/02-security-harden.sh')"
COCKPIT_PASSWORD="$(cat /root/.cockpit-admin-password 2>/dev/null || echo 'not set - run scripts/02-security-harden.sh')"

RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-$HOST_FOR_URLS}"
RANCHER_PASSWORD="$(cat /root/.rancher-bootstrap-password 2>/dev/null || echo 'not set - run scripts/06-rancher.sh')"

cat <<EOF

======================================================================
 VPS setup complete
======================================================================
 Tailscale IP:        ${TAILSCALE_STATUS}

 Cockpit:             https://${HOST_FOR_URLS}:${COCKPIT_HTTP_PORT}
                       https://${HOST_FOR_URLS}:${COCKPIT_HTTPS_PORT}
                       user:     ${COCKPIT_USER}
                       password: ${COCKPIT_PASSWORD}
                       (saved to /root/.cockpit-admin-user and
                       /root/.cockpit-admin-password; PAM login, same
                       account you'd use on the local console - separate
                       from SSH, which stays key-only)

 Rancher:             https://${RANCHER_HOSTNAME}:${RANCHER_HTTPS_PORT}
                       (also on plain port ${RANCHER_HTTP_PORT})
                       user:     admin
                       password: ${RANCHER_PASSWORD}
                       (saved to /root/.rancher-bootstrap-password; you'll
                       be prompted to change it on first login)

 kubectl / helm:      KUBECONFIG=/etc/rancher/k3s/k3s.yaml (already exported
                       via /etc/profile.d/k3s-kubeconfig.sh for new shells)

 Docker (Cockpit):    $(command_exists docker && echo "installed - see the Containers tab in Cockpit" || echo "not installed (run scripts/07-cockpit-dockermanager.sh)")
                       If VPS_ADMIN_USER was just added to the docker group,
                       log out/in (or reboot) before it takes effect.

 Placeholder webserver: $(systemctl is-active --quiet vps-webserver.service 2>/dev/null && echo "running (127.0.0.1:${TAILSCALE_SERVE_PORT})" || echo "not running (run scripts/03-tailscale.sh)")
                       tailnet:  https://${HOST_FOR_SERVE}:${TAILSCALE_SERVE_PORT}
                       public:   $(tailscale funnel status 2>/dev/null | grep -q "${TAILSCALE_SERVE_PORT}" && echo "on - see: tailscale funnel status" || echo "off (TAILSCALE_ENABLE_FUNNEL=false, or Funnel rejected this port)")

 Firewall:            ufw is enabled; only SSH is public. Cockpit, Rancher
                       and the k3s API are reachable ONLY over the
                       tailscale0 interface - connect via Tailscale first.
======================================================================
EOF
