#!/usr/bin/env bash
# Harden the server for exposure to the public internet:
#   - optional non-root sudo admin user with SSH key
#   - SSH: disable root login, disable password auth (only if a key exists)
#   - UFW: default-deny inbound, then every rule in ../network.yaml applied
#     as either public or Tailscale-only, per its `access` field
#   - fail2ban for SSH brute-force protection
#
# Ports and their public/Tailscale-only access are defined in
# ../network.yaml, not here - see that file and README.md's "Security
# model" section. Each port there can still be overridden for a single
# run via an env var named after it (e.g. RANCHER_HTTP_PORT).
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
#   SSH_PORT            - SSH port to keep open (default: from network.yaml)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

up() {
require_root
apt_update_once

SSH_PORT="${SSH_PORT:-$(net_port ssh)}"

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
  COCKPIT_PASSWORD="$(random_password 24)"
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

log "Configuring ufw from ${NETWORK_YAML}..."
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing

# Every port and its public/Tailscale-only access comes from
# network.yaml; a port whose `name` there is e.g. "rancher_http" can
# still be overridden for this run via RANCHER_HTTP_PORT, same as every
# script that opens that port for its own app.
ensure_yq
while IFS=$'\t' read -r name yaml_port access note; do
  env_var="$(echo "$name" | tr '[:lower:]' '[:upper:]')_PORT"
  port="${!env_var:-$yaml_port}"
  case "$access" in
    public)
      ufw allow "${port}/tcp" comment "${note:-$name}"
      ;;
    tailscale)
      # Not reachable from the public internet until scripts/03 brings
      # tailscale0 up.
      ufw allow in on tailscale0 to any port "$port" proto tcp comment "vps-setup: tailscale-only (${name})" || true
      ;;
    *)
      warn "network.yaml: unknown access '${access}' for port '${name}' - skipping."
      ;;
  esac
done < <(yq e '.ports[] | [.name, .port, .access, (.note // "")] | @tsv' "$NETWORK_YAML")

# k3s node-to-node / API traffic, also tailscale-only (not a single fixed
# port, so it isn't one of network.yaml's entries).
ufw allow in on tailscale0 comment "vps-setup: tailscale-only"

ufw --force enable
ok "ufw enabled from network.yaml: public ports open to everyone, tailscale ports reachable only via Tailscale."
}

# Reverts the hardening applied by up(): disables ufw (back to wide open -
# be ready to re-run `up` or configure your own firewall before relying on
# this), restores sshd's stock config, and disables the sshd fail2ban jail.
# Deliberately leaves VPS_ADMIN_USER (if created) and its SSH key/Cockpit
# password in place - removing a login account is destructive enough that
# it should be a separate, explicit decision, not a side effect of turning
# this step off.
down() {
  require_root

  log "Disabling fail2ban's sshd jail..."
  rm -f /etc/fail2ban/jail.d/sshd.local
  systemctl disable --now fail2ban 2>/dev/null || true

  log "Restoring sshd to its distro default config..."
  rm -f /etc/ssh/sshd_config.d/99-vps-setup.conf
  if sshd -t 2>/dev/null; then
    systemctl reload ssh
  else
    warn "sshd -t failed after removing the drop-in; reload it manually once sshd_config is valid again."
  fi

  log "Disabling ufw..."
  ufw --force disable || true

  warn "Security hardening reverted: ufw is disabled (no firewall at all) and" \
       "sshd/fail2ban are back to distro defaults. The admin user/password" \
       "created by 'up' (if any) were left in place. Re-run this step's" \
       "'up' action, or configure your own firewall, before exposing this" \
       "VPS again."
  ok "Security hardening removed."
}

dispatch_action "$@"
