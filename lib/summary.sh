#!/usr/bin/env bash
# Print a final summary of what was installed and how to reach it.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

# net_port's default (no 3rd arg) resolves the *calling script's own*
# package.json - since this file isn't any one feature's run.sh, every
# lookup here names the feature explicitly instead.
COCKPIT_HTTP_PORT="${COCKPIT_HTTP_PORT:-$(net_port cockpit_http cockpit)}"
COCKPIT_HTTPS_PORT="${COCKPIT_HTTPS_PORT:-$(net_port cockpit_https cockpit)}"
RANCHER_HTTP_PORT="${RANCHER_HTTP_PORT:-$(net_port rancher_http rancher)}"
RANCHER_HTTPS_PORT="${RANCHER_HTTPS_PORT:-$(net_port rancher_https rancher)}"
TRAEFIK_DASHBOARD_PORT="${TRAEFIK_DASHBOARD_PORT:-$(net_port traefik_dashboard k3s)}"
ARGOCD_HTTP_PORT="${ARGOCD_HTTP_PORT:-$(net_port argocd_http argocd)}"
ARGOCD_HTTPS_PORT="${ARGOCD_HTTPS_PORT:-$(net_port argocd_https argocd)}"

TAILSCALE_IP="$(tailscale ip -4 2>/dev/null || true)"
HOST_FOR_URLS="${TAILSCALE_IP:-<tailscale-ip>}"
[[ -z "$TAILSCALE_IP" ]] && TAILSCALE_STATUS="not joined yet - run: tailscale up" || TAILSCALE_STATUS="$TAILSCALE_IP"

COCKPIT_USER="$(cat /root/.cockpit-admin-user 2>/dev/null || echo 'not set - run features/security/run.sh')"
COCKPIT_PASSWORD="$(cat /root/.cockpit-admin-password 2>/dev/null || echo 'not set - run features/security/run.sh')"

RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-$HOST_FOR_URLS}"
RANCHER_PASSWORD="$(cat /root/.rancher-bootstrap-password 2>/dev/null || echo 'not set - run features/rancher/run.sh')"

ARGOCD_PASSWORD="$(cat /root/.argocd-admin-password 2>/dev/null || echo 'not set - run features/argocd/run.sh')"

NODE_PUBLIC_IP="$(hostname -I | awk '{print $1}')"

EPINIO_DOMAIN="${EPINIO_DOMAIN:-${NODE_PUBLIC_IP}.sslip.io}"
EPINIO_PASSWORD="$(cat /root/.epinio-admin-password 2>/dev/null || echo 'not set - run features/epinio/run.sh')"

GITHUB_ARC_STATUS="not installed (run: sudo sh dispatch.sh --with-github-arc)"
if command_exists helm && helm status arc-runner-set -n github >/dev/null 2>&1; then
  GITHUB_ARC_STATUS="installed - runner scale set: $(kubectl -n github get autoscalingrunnersets -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo 'see: kubectl -n github get autoscalingrunnersets')"
fi

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

 Docker (Cockpit):    $(command_exists docker && echo "installed - see the Containers tab in Cockpit" || echo "not installed (run features/dockermanager/run.sh)")
                       If VPS_ADMIN_USER was just added to the docker group,
                       log out/in (or reboot) before it takes effect.

 Traefik (k3s):       public: http://${NODE_PUBLIC_IP} and https://${NODE_PUBLIC_IP}
                       (a "letsencrypt" certResolver is configured and
                       ready to use - it won't issue anything until you
                       add the router.tls.certresolver annotation to your
                       own Ingress; see README)
                       dashboard: http://${HOST_FOR_URLS}:${TRAEFIK_DASHBOARD_PORT}/dashboard/
                       (Tailscale-only, no login - see README's Security model)

 ArgoCD:              https://${HOST_FOR_URLS}:${ARGOCD_HTTPS_PORT}
                       (also on plain port ${ARGOCD_HTTP_PORT})
                       user:     admin
                       password: ${ARGOCD_PASSWORD}
                       (saved to /root/.argocd-admin-password; GitOps
                       deployments for the k3s cluster - see README)

 Epinio:              https://epinio.${EPINIO_DOMAIN}
                       user:     admin
                       password: ${EPINIO_PASSWORD}
                       (saved to /root/.epinio-admin-password; deploy an
                       app from source with: epinio push - see README.
                       Public via Traefik like any Ingress, not
                       Tailscale-only - gated by this login, not ufw)

 GitHub ARC:          ${GITHUB_ARC_STATUS}
                       (namespace: github; see README's GitHub Actions
                       Runner Controller (ARC) section)

 kubectl / helm:      KUBECONFIG=/etc/rancher/k3s/k3s.yaml (already exported
                       via /etc/profile.d/k3s-kubeconfig.sh for new shells)

 Firewall:            ufw is enabled; SSH/HTTP/HTTPS are public (Traefik is
                       this VPS's ingress, and so is Epinio, routed through
                       it). Cockpit, Rancher, the Traefik dashboard, ArgoCD,
                       and the k3s API are reachable ONLY over the
                       tailscale0 interface - connect via Tailscale first.
======================================================================
EOF
