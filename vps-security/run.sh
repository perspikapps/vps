#!/bin/sh
# Admin user, SSH hardening, ufw, fail2ban. Env vars: see README.

set -eu
export DEBIAN_FRONTEND=noninteractive
zz-use zz-colors zz-log zz-persist zz-install
# shellcheck disable=SC1091
. zz-colors
# Scripts of this checkout, called (never sourced): addresses, private interface, ports.
vps_network="$(dirname "$0")/../vps-network/run.sh"

GUARD_BIN=/usr/local/sbin/vps-private-ports-guard
GUARD_UNIT=/etc/systemd/system/vps-private-ports-guard.service

# Rules wanted by this run, one ufw spec per line (see fw).
wanted=""

# fw <ufw allow arguments...>: allows a rule and records its spec, so rules a
# previous run recorded but this one no longer wants can be deleted afterwards.
fw() {
    ufw allow "$@"
    printf '%s\n' "$*" >>"$wanted"
}

up() {
    local ssh_port admin_home cockpit_user cockpit_password has_key=0 f sshd_dropin ufw_state
    local name port access note tab spec private_iface private_ip

    ssh_port="$("$vps_network" port ssh)"

    zz-log i "[vps-setup] Installing ufw and fail2ban..."
    zz-install -m  ufw fail2ban

    # --- admin user and SSH key
    if [ -n "${VPS_ADMIN_USER:-}" ]; then
        if id "$VPS_ADMIN_USER" >/dev/null 2>&1; then
            zz-log i "[vps-setup] User ${VPS_ADMIN_USER} already exists."
        else
            zz-log i "[vps-setup] Creating sudo user ${VPS_ADMIN_USER}..."
            adduser --disabled-password --gecos "" "$VPS_ADMIN_USER"
            usermod -aG sudo "$VPS_ADMIN_USER"
        fi
        if [ -n "${VPS_ADMIN_SSH_KEY:-}" ]; then
            admin_home="$(getent passwd "$VPS_ADMIN_USER" | cut -d: -f6)"
            install -d -m 700 -o "$VPS_ADMIN_USER" -g "$VPS_ADMIN_USER" "$admin_home/.ssh"
            touch "$admin_home/.ssh/authorized_keys"
            zz-persist -l -f "$admin_home/.ssh/authorized_keys" "$VPS_ADMIN_SSH_KEY"
            chmod 600 "$admin_home/.ssh/authorized_keys"
            chown "$VPS_ADMIN_USER":"$VPS_ADMIN_USER" "$admin_home/.ssh/authorized_keys"
        fi
    fi

    if [ -n "${VPS_ADMIN_SSH_KEY:-}" ]; then
        install -d -m 700 /root/.ssh
        touch /root/.ssh/authorized_keys
        zz-persist -l -f /root/.ssh/authorized_keys "$VPS_ADMIN_SSH_KEY"
        chmod 600 /root/.ssh/authorized_keys
    fi

    # --- Cockpit login
    cockpit_user="${VPS_ADMIN_USER:-root}"
    cockpit_password="$(zz-persist -f "$VPS_SECRETS_FILE" -s -g 24 COCKPIT_ADMIN_PASSWORD "${VPS_ADMIN_PASSWORD:-}")"
    echo "${cockpit_user}:${cockpit_password}" | chpasswd
    zz-persist -s -f "$VPS_SECRETS_FILE" COCKPIT_ADMIN_USER "$cockpit_user"
    zz-log s "[vps-setup] Cockpit login set: user=${cockpit_user} (password saved to ${VPS_SECRETS_FILE})."

    for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
        if [ -s "$f" ]; then has_key=1; fi
    done

    # --- sshd
    zz-log i "[vps-setup] Hardening sshd_config..."
    sshd_dropin=/etc/ssh/sshd_config.d/99-vps-setup.conf
    {
        echo "Port ${ssh_port}"
        echo "PermitRootLogin prohibit-password"
        echo "X11Forwarding no"
        echo "MaxAuthTries 4"
    } >"$sshd_dropin"

    if [ "$has_key" -eq 1 ]; then
        echo "PasswordAuthentication no" >>"$sshd_dropin"
        zz-log s "[vps-setup] SSH key detected: disabling password authentication."
    else
        zz-log w "[vps-setup] No SSH key provided (VPS_ADMIN_SSH_KEY unset): leaving password authentication enabled."
    fi

    sshd -t -f /etc/ssh/sshd_config
    if systemctl is-active --quiet ssh.service; then
        systemctl reload ssh
        zz-log s "[vps-setup] sshd hardened and reloaded."
    else
        zz-log w "[vps-setup] ssh.service is not active: sshd config written but not reloaded (it applies on next start)."
    fi

    # --- fail2ban
    zz-log i "[vps-setup] Enabling fail2ban for sshd..."
    cat >/etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled = true
port = ${ssh_port}
maxretry = 5
bantime = 1h
findtime = 10m
EOF
    systemctl enable --now fail2ban
    systemctl restart fail2ban

    # --- ufw
    zz-log i "[vps-setup] Configuring ufw from every feature's package.json..."
    # Upsert, no window without rules: every rule goes through fw(), which records its
    # spec; rules recorded by the previous run but not wanted now are deleted after the
    # new ones are in. No record yet (first run, or a host set up by an older version
    # that reset and rebuilt): one reset to start clean.
    ufw_state=/var/lib/vps-security-ufw.rules
    [ -f "$ufw_state" ] || ufw --force reset >/dev/null
    wanted="$(mktemp)"
    ufw default deny incoming
    ufw default allow outgoing

    private_iface="$("$vps_network" private-interface)"
    private_ip="$("$vps_network" private-address)"
    if [ -z "$private_iface" ]; then
        zz-log w "[vps-setup] No private interface (VPS_PRIVATE_INTERFACE unset, and no step persisted one): private-access ports stay closed."
    elif [ -z "$private_ip" ]; then
        zz-log w "[vps-setup] ${private_iface} has no IPv4 address yet: private-access ports stay closed."
    fi

    tab="$(printf '\t')"
    while IFS="$tab" read -r name port access note; do
        case "$access" in
            public)
                fw "${port}/tcp" comment "${note:-$name}"
                ;;
            private)
                [ -z "$private_ip" ] || fw in on "$private_iface" to "$private_ip" port "$port" proto tcp comment "vps-setup: private-only (${name})" || true
                ;;
            *)
                zz-log w "[vps-setup] unknown access '${access}' for port '${name}' - skipping."
                ;;
        esac
    done <<EOF
$("$vps_network" ports)
EOF

    if [ -f "$ufw_state" ]; then
        # shellcheck disable=SC2046
        while IFS= read -r spec; do
            grep -qxF "$spec" "$wanted" || ufw --force delete allow ${spec%% comment *} || true
        done <"$ufw_state"
    fi
    mv "$wanted" "$ufw_state"

    ufw --force enable
    zz-log s "[vps-setup] ufw enabled from every feature's package.json: public ports open to everyone, private ports reachable only on ${private_ip:-<no private address>} (${private_iface:-no private interface})."

    install_private_guard "${private_iface:--}" "$("$vps_network" ports | awk -F'\t' '$3 == "private" { print $2 }')"
}

# ufw only filters INPUT. Ports published by k3s's ServiceLB or by Docker are
# DNAT-ed and go through FORWARD, where those two accept them ahead of ufw: a
# "private" Rancher, Traefik dashboard or Dokploy UI would answer on the public
# interface. This drops DNAT-ed connections to the private ports arriving on the
# default-route interface (unless that is the private one). FORWARD position 1,
# re-inserted on every run: k3s and Docker must be (re)started before the rule
# is final, so their steps call "$vps_network" reapply-guard once they are up.
install_private_guard() {
    local private="$1" ports="$2"

    cat >"$GUARD_BIN" <<'GUARD'
#!/bin/sh
# usage: vps-private-ports-guard add|del <private-interface|-> <port>...
action="$1" private="$2"
shift 2
iface="$(ip -4 route show default | awk '{print $5; exit}')"
[ -n "$iface" ] && [ "$iface" != "$private" ] || exit 0
for port in "$@"; do
  rule="-i $iface -p tcp -m conntrack --ctstate DNAT --ctorigdstport $port -j DROP"
  while iptables -D FORWARD $rule 2>/dev/null; do :; done
  if [ "$action" = add ]; then iptables -I FORWARD 1 $rule; fi
done
GUARD
    chmod 755 "$GUARD_BIN"
    # shellcheck disable=SC2086
    cat >"$GUARD_UNIT" <<UNIT
[Unit]
Description=Keep private-access ports off the public interface
After=network-online.target docker.service k3s.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${GUARD_BIN} add ${private} $(printf '%s ' $ports)

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable vps-private-ports-guard.service
    systemctl restart vps-private-ports-guard.service
}

down() {
    if [ -f "$GUARD_UNIT" ]; then
        zz-log i "[vps-setup] Removing the private-ports FORWARD guard..."
        # The rules are in iptables, not in the unit: delete them with the ports the unit added.
        # shellcheck disable=SC2046
        "$GUARD_BIN" del - $(sed -n 's/^ExecStart=[^ ]* add [^ ]* //p' "$GUARD_UNIT") || true
        systemctl disable vps-private-ports-guard.service 2>/dev/null || true
        rm -f "$GUARD_UNIT" "$GUARD_BIN"
        systemctl daemon-reload
    fi

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
    rm -f /var/lib/vps-security-ufw.rules

    zz-log w "[vps-setup] Security hardening reverted: ufw is disabled (no firewall at all) and" \
        "sshd/fail2ban are back to distro defaults. The admin user/password" \
        "created by 'up' (if any) were left in place. Re-run this step's" \
        "'up' action, or configure your own firewall, before exposing this" \
        "VPS again."
    zz-log s "[vps-setup] Security hardening removed."
}

summary() {
    cat <<EOF
 Firewall:            ufw is enabled; SSH/HTTP/HTTPS are public (Traefik is
                       this VPS's ingress). Cockpit, Rancher, the Traefik
                       dashboard, the Dokploy admin UI, and the k3s API are reachable ONLY over
                       the private interface ($("$vps_network" private-interface || true)) - connect
                       to that network first.
EOF
}

case "${1:-}" in
    up | down) "$1" ;;
    summary) if command -v summary >/dev/null 2>&1; then summary; fi ;;
    *) zz-log e "Usage: $0 up|down|summary" && exit 1 ;;
esac
