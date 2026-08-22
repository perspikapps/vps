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

TAILSCALE_IP="$(tailscale ip -4 2>/dev/null || echo 'not joined yet - run: tailscale up')"

cat <<EOF

======================================================================
 VPS setup complete
======================================================================
 Tailscale IP:        ${TAILSCALE_IP}

 Cockpit:             https://<tailscale-ip>:${COCKPIT_HTTP_PORT}
                       https://<tailscale-ip>:${COCKPIT_HTTPS_PORT}

 Rancher:              https://<tailscale-ip or hostname>:${RANCHER_HTTPS_PORT}
                       (also on plain port ${RANCHER_HTTP_PORT})
                       bootstrap password: /root/.rancher-bootstrap-password

 kubectl / helm:      KUBECONFIG=/etc/rancher/k3s/k3s.yaml (already exported
                       via /etc/profile.d/k3s-kubeconfig.sh for new shells)

 Firewall:             ufw is enabled; only SSH is public. Cockpit, Rancher
                       and the k3s API are reachable ONLY over the
                       tailscale0 interface - connect via Tailscale first.
======================================================================
EOF
