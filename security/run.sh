#!/usr/bin/env bash
# Admin user, SSH hardening, ufw, fail2ban. Env vars: see README.

set -euo pipefail
command -v zz_use >/dev/null 2>&1 || { echo "zz_use not found on PATH - run this repo's setup.sh first: curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/setup.sh | sh" >&2; exit 1; }
zz_use "perspikapps/vps/common@${VPS_SETUP_REPO_REF:-main}"
# shellcheck disable=SC1091
. common

up() {
require_root
apt_update_once

SSH_PORT="${SSH_PORT:-$(net_port ssh)}"

zz_log i "[vps-setup] Installing ufw and fail2ban..."
apt_install ufw fail2ban

if [[ -n "${VPS_ADMIN_USER:-}" ]]; then
  if id "$VPS_ADMIN_USER" >/dev/null 2>&1; then
    zz_log i "[vps-setup] User ${VPS_ADMIN_USER} already exists."
  else
    zz_log i "[vps-setup] Creating sudo user ${VPS_ADMIN_USER}..."
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

HAS_KEY=0
for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
  [[ -s "$f" ]] 2>/dev/null && HAS_KEY=1
done

zz_log i "[vps-setup] Hardening sshd_config..."
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
  zz_log w "[vps-setup] No SSH key provided (VPS_ADMIN_SSH_KEY unset): leaving password authentication enabled."
fi

sshd -t -f /etc/ssh/sshd_config && systemctl reload ssh
ok "sshd hardened and reloaded."

zz_log i "[vps-setup] Enabling fail2ban for sshd..."
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

zz_log i "[vps-setup] Configuring ufw from every feature's package.json..."
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing

while IFS=$'\t' read -r name pkg_port access note; do
  env_var="$(echo "$name" | tr '[:lower:]' '[:upper:]')_PORT"
  port="${!env_var:-$pkg_port}"
  case "$access" in
    public)
      ufw allow "${port}/tcp" comment "${note:-$name}"
      ;;
    tailscale)
      ufw allow in on tailscale0 to any port "$port" proto tcp comment "vps-setup: tailscale-only (${name})" || true
      ;;
    *)
      zz_log w "[vps-setup] unknown access '${access}' for port '${name}' - skipping."
      ;;
  esac
done < <(all_network_ports)

ufw allow in on tailscale0 comment "vps-setup: tailscale-only"

ufw --force enable
ok "ufw enabled from every feature's package.json: public ports open to everyone, tailscale ports reachable only via Tailscale."
}

down() {
  require_root

  zz_log i "[vps-setup] Disabling fail2ban's sshd jail..."
  rm -f /etc/fail2ban/jail.d/sshd.local
  systemctl disable --now fail2ban 2>/dev/null || true

  zz_log i "[vps-setup] Restoring sshd to its distro default config..."
  rm -f /etc/ssh/sshd_config.d/99-vps-setup.conf
  if sshd -t 2>/dev/null; then
    systemctl reload ssh
  else
    zz_log w "[vps-setup] sshd -t failed after removing the drop-in; reload it manually once sshd_config is valid again."
  fi

  zz_log i "[vps-setup] Disabling ufw..."
  ufw --force disable || true

  zz_log w "[vps-setup] Security hardening reverted: ufw is disabled (no firewall at all) and" \
       "sshd/fail2ban are back to distro defaults. The admin user/password" \
       "created by 'up' (if any) were left in place. Re-run this step's" \
       "'up' action, or configure your own firewall, before exposing this" \
       "VPS again."
  ok "Security hardening removed."
}

dispatch_action "$@"
