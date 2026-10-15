#!/usr/bin/env bash
# Admin user, SSH hardening, ufw, fail2ban. Env vars: see README.

set -euo pipefail
zz-use "perspikapps/vps/vps-common@${VPS_SETUP_REPO_REF:-main}" zz-persist
# shellcheck disable=SC1091
. vps-common

up() {
apt_update_once

SSH_PORT="$(net_port ssh)"

zz-log i "[vps-setup] Installing ufw and fail2ban..."
apt_install ufw fail2ban

if [[ -n "${VPS_ADMIN_USER:-}" ]]; then
  if id "$VPS_ADMIN_USER" >/dev/null 2>&1; then
    zz-log i "[vps-setup] User ${VPS_ADMIN_USER} already exists."
  else
    zz-log i "[vps-setup] Creating sudo user ${VPS_ADMIN_USER}..."
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
COCKPIT_PASSWORD="${VPS_ADMIN_PASSWORD:-$(vps_secret COCKPIT_ADMIN_PASSWORD /root/.cockpit-admin-password)}"
[[ -n "$COCKPIT_PASSWORD" ]] || COCKPIT_PASSWORD="$(random_password 24)"
echo "${COCKPIT_USER}:${COCKPIT_PASSWORD}" | chpasswd
vps_secret_set COCKPIT_ADMIN_PASSWORD "$COCKPIT_PASSWORD" /root/.cockpit-admin-password
vps_secret_set COCKPIT_ADMIN_USER "$COCKPIT_USER" /root/.cockpit-admin-user
ok "Cockpit login set: user=${COCKPIT_USER} (password saved to ${VPS_SECRETS_FILE})."

HAS_KEY=0
for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
  [[ -s "$f" ]] 2>/dev/null && HAS_KEY=1
done

zz-log i "[vps-setup] Hardening sshd_config..."
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
  zz-log w "[vps-setup] No SSH key provided (VPS_ADMIN_SSH_KEY unset): leaving password authentication enabled."
fi

sshd -t -f /etc/ssh/sshd_config
if systemctl is-active --quiet ssh.service; then
  systemctl reload ssh
  ok "sshd hardened and reloaded."
else
  zz-log w "[vps-setup] ssh.service is not active: sshd config written but not reloaded (it applies on next start)."
fi

zz-log i "[vps-setup] Enabling fail2ban for sshd..."
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

zz-log i "[vps-setup] Configuring ufw from every feature's package.json..."
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing

PRIVATE_IFACE="$(private_interface)"
if [[ -z "$PRIVATE_IFACE" ]]; then
  zz-log w "[vps-setup] No private interface (VPS_PRIVATE_INTERFACE unset, and no step persisted one): private-access ports stay closed."
fi

while IFS=$'\t' read -r name port access note; do
  case "$access" in
    public)
      ufw allow "${port}/tcp" comment "${note:-$name}"
      ;;
    private)
      [[ -z "$PRIVATE_IFACE" ]] || ufw allow in on "$PRIVATE_IFACE" to any port "$port" proto tcp comment "vps-setup: private-only (${name})" || true
      ;;
    *)
      zz-log w "[vps-setup] unknown access '${access}' for port '${name}' - skipping."
      ;;
  esac
done < <(all_network_ports)

[[ -z "$PRIVATE_IFACE" ]] || ufw allow in on "$PRIVATE_IFACE" comment "vps-setup: private-only"

ufw --force enable
ok "ufw enabled from every feature's package.json: public ports open to everyone, private ports reachable only via ${PRIVATE_IFACE:-<no private interface>}."
}

down() {

  zz-log i "[vps-setup] Disabling fail2ban's sshd jail..."
  rm -f /etc/fail2ban/jail.d/sshd.local
  systemctl disable --now fail2ban 2>/dev/null || true

  zz-log i "[vps-setup] Restoring sshd to its distro default config..."
  rm -f /etc/ssh/sshd_config.d/99-vps-setup.conf
  if sshd -t 2>/dev/null; then
    if systemctl is-active --quiet ssh.service; then
      systemctl reload ssh
    else
      zz-log w "[vps-setup] ssh.service is not active: nothing to reload."
    fi
  else
    zz-log w "[vps-setup] sshd -t failed after removing the drop-in; reload it manually once sshd_config is valid again."
  fi

  zz-log i "[vps-setup] Disabling ufw..."
  ufw --force disable || true

  zz-log w "[vps-setup] Security hardening reverted: ufw is disabled (no firewall at all) and" \
       "sshd/fail2ban are back to distro defaults. The admin user/password" \
       "created by 'up' (if any) were left in place. Re-run this step's" \
       "'up' action, or configure your own firewall, before exposing this" \
       "VPS again."
  ok "Security hardening removed."
}

summary() {
  cat <<EOF
 Firewall:            ufw is enabled; SSH/HTTP/HTTPS are public (Traefik is
                       this VPS's ingress). Cockpit, Rancher, the Traefik
                       dashboard, and the k3s API are reachable ONLY over
                       the private interface ($(private_interface || true)) - connect
                       to that network first.
EOF
}

dispatch_action "$@"
