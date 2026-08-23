#!/usr/bin/env bash
# Harden the server for exposure to the public internet:
#   - optional non-root sudo admin user with SSH key
#   - SSH: disable root login, disable password auth (only if a key exists)
#   - UFW: default-deny inbound, allow SSH publicly, allow the Cockpit/Rancher
#     ports ONLY over the Tailscale interface (not the public internet)
#   - fail2ban for SSH brute-force protection
#
# Env vars:
#   VPS_ADMIN_USER      - optional non-root user to create (default: unset/skip)
#   VPS_ADMIN_SSH_KEY   - public key to authorize for VPS_ADMIN_USER and root
#   VPS_ADMIN_PASSWORD  - Cockpit/console login password for VPS_ADMIN_USER (or
#                         root if unset). Default: random, saved to
#                         /root/.cockpit-admin-password. This is separate from
#                         SSH: SSH password auth stays disabled once a key is
#                         present, this password is only for logging into
#                         Cockpit (and the local console) via PAM.
#   SSH_PORT            - SSH port to keep open (default: 22)
#   COCKPIT_HTTP_PORT   - default 9080
#   COCKPIT_HTTPS_PORT  - default 9083
#   RANCHER_HTTP_PORT   - default 8080
#   RANCHER_HTTPS_PORT  - default 8083
#   ALLOW_PUBLIC_WEB    - "true" to also allow 80/443 publicly (default: false)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

require_root
apt_update_once

SSH_PORT="${SSH_PORT:-22}"
COCKPIT_HTTP_PORT="${COCKPIT_HTTP_PORT:-9080}"
COCKPIT_HTTPS_PORT="${COCKPIT_HTTPS_PORT:-9083}"
RANCHER_HTTP_PORT="${RANCHER_HTTP_PORT:-8080}"
RANCHER_HTTPS_PORT="${RANCHER_HTTPS_PORT:-8083}"
ALLOW_PUBLIC_WEB="${ALLOW_PUBLIC_WEB:-false}"

log "Installing ufw and fail2ban..."
apt_install ufw fail2ban

if [[ -n "${VPS_ADMIN_USER:-}" ]]; then
  if id "$VPS_ADMIN_USER" >/dev/null 2>&1; then
    log "User ${VPS_ADMIN_USER} already exists."
  else
    log "Creating sudo user ${VPS_ADMIN_USER}..."
    adduser --disabled-password --gecos "" "$VPS_ADMIN_USER"
    usermod -aG sudo "$VPS_ADMIN_USER"
  fi
  if [[ -n "${VPS_ADMIN_SSH_KEY:-}" ]]; then
    ADMIN_HOME="$(getent passwd "$VPS_ADMIN_USER" | cut -d: -f6)"
    install -d -m 700 -o "$VPS_ADMIN_USER" -g "$VPS_ADMIN_USER" "$ADMIN_HOME/.ssh"
    touch "$ADMIN_HOME/.ssh/authorized_keys"
    ensure_line "$VPS_ADMIN_SSH_KEY" "$ADMIN_HOME/.ssh/authorized_keys"
    chmod 600 "$ADMIN_HOME/.ssh/authorized_keys"
    chown "$VPS_ADMIN_USER":"$VPS_ADMIN_USER" "$ADMIN_HOME/.ssh/authorized_keys"
  fi
fi

if [[ -n "${VPS_ADMIN_SSH_KEY:-}" ]]; then
  install -d -m 700 /root/.ssh
  touch /root/.ssh/authorized_keys
  ensure_line "$VPS_ADMIN_SSH_KEY" /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
fi

# Cockpit authenticates via PAM against a real Linux account/password, which
# is independent of SSH key auth - without this, adduser --disabled-password
# above leaves no way to log into Cockpit at all.
COCKPIT_USER="${VPS_ADMIN_USER:-root}"
COCKPIT_PW_FILE=/root/.cockpit-admin-password
if [[ -n "${VPS_ADMIN_PASSWORD:-}" ]]; then
  COCKPIT_PASSWORD="$VPS_ADMIN_PASSWORD"
elif [[ -f "$COCKPIT_PW_FILE" ]]; then
  COCKPIT_PASSWORD="$(cat "$COCKPIT_PW_FILE")"
else
  COCKPIT_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"
fi
echo "${COCKPIT_USER}:${COCKPIT_PASSWORD}" | chpasswd
umask 077
echo "$COCKPIT_PASSWORD" > "$COCKPIT_PW_FILE"
echo "$COCKPIT_USER" > /root/.cockpit-admin-user
umask 022
ok "Cockpit login set: user=${COCKPIT_USER} (password saved to ${COCKPIT_PW_FILE})."

# Only disable password auth if at least one authorized_keys file has a key,
# otherwise we'd lock everyone out.
HAS_KEY=0
for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
  [[ -s "$f" ]] 2>/dev/null && HAS_KEY=1
done

log "Hardening sshd_config..."
SSHD_DROPIN=/etc/ssh/sshd_config.d/99-vps-setup.conf
{
  echo "Port ${SSH_PORT}"
  echo "PermitRootLogin prohibit-password"
  echo "X11Forwarding no"
  echo "MaxAuthTries 4"
} > "$SSHD_DROPIN"

if [[ "$HAS_KEY" -eq 1 ]]; then
  echo "PasswordAuthentication no" >> "$SSHD_DROPIN"
  ok "SSH key detected: disabling password authentication."
else
  warn "No SSH key provided (VPS_ADMIN_SSH_KEY unset): leaving password authentication enabled."
fi

sshd -t -f /etc/ssh/sshd_config && systemctl reload ssh
ok "sshd hardened and reloaded."

log "Enabling fail2ban for sshd..."
cat > /etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled = true
port = ${SSH_PORT}
maxretry = 5
bantime = 1h
findtime = 10m
EOF
systemctl enable --now fail2ban
systemctl restart fail2ban

log "Configuring ufw..."
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp" comment "SSH"

if [[ "$ALLOW_PUBLIC_WEB" == "true" ]]; then
  ufw allow 80/tcp comment "HTTP"
  ufw allow 443/tcp comment "HTTPS"
fi

# Cockpit and Rancher are only reachable over the Tailscale interface, never
# on the public internet, until scripts/03 brings tailscale0 up.
for port in "$COCKPIT_HTTP_PORT" "$COCKPIT_HTTPS_PORT" "$RANCHER_HTTP_PORT" "$RANCHER_HTTPS_PORT"; do
  ufw allow in on tailscale0 to any port "$port" proto tcp comment "vps-setup: tailscale-only" || true
done
# k3s node-to-node / API traffic, also tailscale-only.
ufw allow in on tailscale0 comment "vps-setup: tailscale-only"

ufw --force enable
ok "ufw enabled: SSH open publicly; Cockpit/Rancher/k3s reachable only via Tailscale."
