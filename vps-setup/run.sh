#!/usr/bin/env bash
# Thin wrapper around zz-setup: runs every step of this repo in order (or just
# the ones asked for) - feature discovery, the skip/up/down menu, dependency
# resolution, input prompts and persistence are zz-setup's - then prints the
# final connection summary. Installed and invoked as `vps-setup` - see
# README's "Running vps-setup" section.
#
# What stays here: the Ubuntu/root checks, the legacy --skip-<step> /
# --with-<step> / --only-<step> / --down-<step> / --force-down flags
# (translated to zz-setup's -s/-w/-o/-d/-F lists), the shell-syntax settings
# file (VPS_SETUP_ENV_FILE) and the summary.

set -euo pipefail

# Settings file written at provisioning time (cloud-init): shell syntax, so it
# is sourced here, never rewritten. zz-setup keeps its own plain-text state
# for answers typed in the menu.
ENV_FILE="${VPS_SETUP_ENV_FILE:-/etc/vps-setup.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

zz-use "perspikapps/vps/vps-common@${VPS_SETUP_REPO_REF:-main}" zz-setup
# shellcheck disable=SC1091
. vps-common

# -h only prints zz-setup's help, which needs neither.
[[ " $* " == *" -h "* ]] || { require_root; require_ubuntu; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/../vps-common/run.sh" ]]; then
  # Full local checkout (dev clone, `bash vps-setup/run.sh`): used in place.
  CHECKOUT="$(cd "$SCRIPT_DIR/.." && pwd)"
  REPO="$CHECKOUT"
else
  # Standalone zz-use install: zz-setup fetches the whole repo into /opt/<repo>.
  REPO_URL="${VPS_SETUP_REPO_URL:-https://github.com/perspikapps/vps.git}"
  REPO_PATH="$(printf '%s' "$REPO_URL" | sed -E 's#^[A-Za-z+]+://[^/]+/##; s#\.git$##')"
  export ZZ_SETUP_URL_BASE="${REPO_URL%/"$REPO_PATH"*}"
  export ZZ_SETUP_DIR="${ZZ_SETUP_DIR:-/opt}"
  CHECKOUT="$ZZ_SETUP_DIR/${REPO_PATH##*/}"
  REPO="$REPO_PATH@${VPS_SETUP_REPO_REF:-main}"
fi

# Legacy flags -> zz-setup lists; anything else (e.g. -h) goes through as is.
skip=() with=() only=() down=() opts=()
for arg in "$@"; do
  case "$arg" in
    --skip-*) skip+=("${arg#--skip-}") ;;
    --with-*) with+=("${arg#--with-}") ;;
    --only-*) only+=("${arg#--only-}") ;;
    --down-*) down+=("${arg#--down-}") ;;
    --force-down) opts+=(-F) ;;
    *) opts+=("$arg") ;;
  esac
done
join() { local IFS=,; printf '%s' "$*"; }
[[ ${#skip[@]} -eq 0 ]] || opts+=(-s "$(join "${skip[@]}")")
[[ ${#with[@]} -eq 0 ]] || opts+=(-w "$(join "${with[@]}")")
[[ ${#only[@]} -eq 0 ]] || opts+=(-o "$(join "${only[@]}")")
[[ ${#down[@]} -eq 0 ]] || opts+=(-d "$(join "${down[@]}")")

zz-setup "$REPO" "${opts[@]}"

# vps-common's net_port reads every feature's package.json from here.
VPS_SETUP_ROOT="$CHECKOUT"

# --- summary: final connection info, printed after every run (also
# callable on its own afterwards - see README's "Running vps-setup"
# section - since none of the values below depend on what this run just
# did versus a previous one).

COCKPIT_HTTP_PORT="${COCKPIT_HTTP_PORT:-$(net_port cockpit_http vps-cockpit)}"
COCKPIT_HTTPS_PORT="${COCKPIT_HTTPS_PORT:-$(net_port cockpit_https vps-cockpit)}"
RANCHER_HTTP_PORT="${RANCHER_HTTP_PORT:-$(net_port rancher_http vps-rancher)}"
RANCHER_HTTPS_PORT="${RANCHER_HTTPS_PORT:-$(net_port rancher_https vps-rancher)}"
TRAEFIK_DASHBOARD_PORT="${TRAEFIK_DASHBOARD_PORT:-$(net_port traefik_dashboard vps-k3s)}"

TAILSCALE_IP="$(tailscale ip -4 2>/dev/null || true)"
HOST_FOR_URLS="${TAILSCALE_IP:-<tailscale-ip>}"
[[ -z "$TAILSCALE_IP" ]] && TAILSCALE_STATUS="not joined yet - run: tailscale up" || TAILSCALE_STATUS="$TAILSCALE_IP"

COCKPIT_USER="$(cat /root/.cockpit-admin-user 2>/dev/null || echo 'not set - run vps-security/run.sh')"
COCKPIT_PASSWORD="$(cat /root/.cockpit-admin-password 2>/dev/null || echo 'not set - run vps-security/run.sh')"

RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-$HOST_FOR_URLS}"
RANCHER_PASSWORD="$(cat /root/.rancher-bootstrap-password 2>/dev/null || echo 'not set - run vps-rancher/run.sh')"

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

 Docker (Cockpit):    $(command_exists docker && echo "installed - see the Containers tab in Cockpit" || echo "not installed (run vps-dockermanager/run.sh)")
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
                       vps-marketplace step) - install ArgoCD, Epinio, or
                       any other chart from this repo's catalog from
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
