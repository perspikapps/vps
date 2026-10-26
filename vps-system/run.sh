#!/bin/sh
# Base system update and common CLI utilities.

set -eu
export DEBIAN_FRONTEND=noninteractive # apt only; ignored elsewhere
zz-use zz-colors zz-log zz-persist zz-install ../vps-network
# shellcheck disable=SC1091
. zz-colors

up() {
    local domain

    zz-log i "[vps-setup] Upgrading existing packages and installing base utilities..."
    zz-install -f -m ca-certificates curl wget git jq unzip htop net-tools
    # Same tools, named differently outside Debian (gnupg2 on Amazon Linux, gpg2 on SUSE).
    zz-install -m gnupg dnf=gnupg2 zypper=gpg2

    zz-log i "[vps-setup] Enabling unattended security upgrades..."
    if command -v apt-get >/dev/null 2>&1; then
        zz-install -m lsb-release apt-transport-https software-properties-common unattended-upgrades
        dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null 2>&1 || true
        zz-persist -l -f /etc/apt/apt.conf.d/50unattended-upgrades-local 'Unattended-Upgrade::Automatic-Reboot "false";'
        cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF2'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF2
    elif command -v dnf >/dev/null 2>&1; then
        zz-install -m dnf-automatic
        sed -i -e 's/^upgrade_type *=.*/upgrade_type = security/' -e 's/^apply_updates *=.*/apply_updates = yes/' /etc/dnf/automatic.conf
        systemctl enable --now dnf-automatic.timer
    else
        zz-log w "[vps-setup] No unattended security upgrades on this distribution: run 'zypper patch' on your own schedule."
    fi

    if [ -n "${TZ:-}" ]; then
        zz-log i "[vps-setup] Setting timezone to ${TZ}..."
        timedatectl set-timezone "$TZ" || zz-log w "[vps-setup] Could not set timezone ${TZ}"
    fi

    # Wildcard DNS for apps that need subdomains; unset = nip.io, worked out where it is used.
    if [ -n "${EXTERNAL_DOMAIN:-}" ]; then
        domain="${EXTERNAL_DOMAIN#\*.}"
        printf '%s\n' "$domain" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$' ||
            { zz-log e "[vps-setup] EXTERNAL_DOMAIN must be a bare domain like apps.example.com (got '${EXTERNAL_DOMAIN}')." && exit 1; }
        vps-network set-external-domain "$domain"
        zz-log i "[vps-setup] Wildcard DNS: *.${domain} (point it at this VPS)."
    else
        zz-log i "[vps-setup] No EXTERNAL_DOMAIN: apps needing wildcard DNS fall back to <ip>.nip.io."
    fi

    zz-log s "[vps-setup] Base system is up to date."
}

case "${1:-}" in
    up | down) "$1" ;;
    summary) if command -v summary >/dev/null 2>&1; then summary; fi ;;
    *) zz-log e "Usage: $0 up|down|summary" && exit 1 ;;
esac
