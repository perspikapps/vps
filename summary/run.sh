#!/usr/bin/env bash
# Print a final summary of what was installed and how to reach it.

set -euo pipefail
command -v zz_use >/dev/null 2>&1 || { echo "zz_use not found on PATH - run this repo's setup.sh first: curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/setup.sh | sh" >&2; exit 1; }
zz_use "perspikapps/vps/common@${VPS_SETUP_REPO_REF:-main}"
# shellcheck disable=SC1091
. common

COCKPIT_HTTP_PORT="${COCKPIT_HTTP_PORT:-$(net_port cockpit_http cockpit)}"
COCKPIT_HTTPS_PORT="${COCKPIT_HTTPS_PORT:-$(net_port cockpit_https cockpit)}"
RANCHER_HTTP_PORT="${RANCHER_HTTP_PORT:-$(net_port rancher_http rancher)}"
RANCHER_HTTPS_PORT="${RANCHER_HTTPS_PORT:-$(net_port rancher_https rancher)}"
TRAEFIK_DASHBOARD_PORT="${TRAEFIK_DASHBOARD_PORT:-$(net_port traefik_dashboard k3s)}"

TAILSCALE_IP="$(tailscale ip -4 2>/dev/null || true)"
HOST_FOR_URLS="${TAILSCALE_IP:-<tailscale-ip>}"
[[ -z "$TAILSCALE_IP" ]] && TAILSCALE_STATUS="not joined yet - run: tailscale up" || TAILSCALE_STATUS="$TAILSCALE_IP"

COCKPIT_USER="$(cat /root/.cockpit-admin-user 2>/dev/null || echo 'not set - run security/run.sh')"
COCKPIT_PASSWORD="$(cat /root/.cockpit-admin-password 2>/dev/null || echo 'not set - run security/run.sh')"

RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-$HOST_FOR_URLS}"
RANCHER_PASSWORD="$(cat /root/.rancher-bootstrap-password 2>/dev/null || echo 'not set - run rancher/run.sh')"

NODE_PUBLIC_IP="$(hostname -I | awk '{print $1}')"

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

 Docker (Cockpit):    $(command_exists docker && echo "installed - see the Containers tab in Cockpit" || echo "not installed (run dockermanager/run.sh)")
                       If VPS_ADMIN_USER was just added to the docker group,
                       log out/in (or reboot) before it takes effect.

 Traefik (k3s):       public: http://${NODE_PUBLIC_IP} and https://${NODE_PUBLIC_IP}
                       (a "letsencrypt" certResolver is configured and
                       ready to use - it won't issue anything until you
                       add the router.tls.certresolver annotation to your
                       own Ingress; see README)
                       dashboard: http://${HOST_FOR_URLS}:${TRAEFIK_DASHBOARD_PORT}/dashboard/
                       (Tailscale-only, no login - see README's Security model)

 Marketplace:         Apps & Marketplace -> Repositories in Rancher should
                       list "perspikapps-vps" (registered by the
                       marketplace step) - install ArgoCD, Epinio, or any
                       other chart from this repo's catalog from
                       Apps & Marketplace -> Charts. See README's
                       "Rancher Marketplace" section.

 kubectl / helm:      KUBECONFIG=/etc/rancher/k3s/k3s.yaml (already exported
                       via /etc/profile.d/k3s-kubeconfig.sh for new shells)

 Firewall:            ufw is enabled; SSH/HTTP/HTTPS are public (Traefik is
                       this VPS's ingress). Cockpit, Rancher, the Traefik
                       dashboard, and the k3s API are reachable ONLY over
                       the tailscale0 interface - connect via Tailscale
                       first.
======================================================================
EOF
