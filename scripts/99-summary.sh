#!/usr/bin/env bash
# Print a final summary of what was installed and how to reach it.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

COCKPIT_HTTP_PORT="${COCKPIT_HTTP_PORT:-9080}"
COCKPIT_HTTPS_PORT="${COCKPIT_HTTPS_PORT:-9083}"
RANCHER_HTTP_PORT="${RANCHER_HTTP_PORT:-7080}"
RANCHER_HTTPS_PORT="${RANCHER_HTTPS_PORT:-7083}"

TAILSCALE_IP="$(tailscale ip -4 2>/dev/null || true)"
HOST_FOR_URLS="${TAILSCALE_IP:-<tailscale-ip>}"
[[ -z "$TAILSCALE_IP" ]] && TAILSCALE_STATUS="not joined yet - run: tailscale up" || TAILSCALE_STATUS="$TAILSCALE_IP"

COCKPIT_USER="$(cat /root/.cockpit-admin-user 2>/dev/null || echo 'not set - run scripts/02-security-harden.sh')"
COCKPIT_PASSWORD="$(cat /root/.cockpit-admin-password 2>/dev/null || echo 'not set - run scripts/02-security-harden.sh')"

RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-$HOST_FOR_URLS}"
RANCHER_PASSWORD="$(cat /root/.rancher-bootstrap-password 2>/dev/null || echo 'not set - run scripts/06-rancher.sh')"

CODER_HTTP_PORT="${CODER_HTTP_PORT:-6080}"
CODER_HOSTNAME="${CODER_HOSTNAME:-$HOST_FOR_URLS}"

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

EOF

if systemctl list-unit-files 2>/dev/null | grep -q '^laranode'; then
  LARANODE_STATE="$(systemctl is-active --quiet laranode-queue.service 2>/dev/null && echo running || echo installed)"
  cat <<EOF

 Laranode (opt-in):   ${LARANODE_STATE} - reachable on the ports its own
                       installer opened (public by default; see
                       LARANODE_TAILSCALE_ONLY). Credentials were printed
                       once by its installer, not re-shown here.
EOF
fi

if command_exists kubectl && kubectl -n coder get deploy coder >/dev/null 2>&1; then
  CODER_ADMIN_PASSWORD="$(cat /root/.coder-admin-password 2>/dev/null || echo 'not set - run scripts/09-coder.sh')"
  cat <<EOF

 Coder (opt-in):      http://${CODER_HOSTNAME}:${CODER_HTTP_PORT}
                       user:     ${CODER_ADMIN_USERNAME:-admin}
                       password: ${CODER_ADMIN_PASSWORD}
                       (saved to /root/.coder-admin-password)
EOF
fi

cat <<EOF

 Firewall:            ufw is enabled; only SSH is public. Cockpit, Rancher,
                       Coder, and the k3s API are reachable ONLY over the
                       tailscale0 interface - connect via Tailscale first.
======================================================================
EOF
