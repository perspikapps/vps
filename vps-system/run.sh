#!/bin/sh
# Base system update and common CLI utilities.

set -eu
# Source the vps-common of this checkout (always the version of the step); a step
# installed on its own gets the one zz-use fetches.
common="$(dirname "$0")/../vps-common/run.sh"
if [ ! -f "$common" ]; then
    zz-use "perspikapps/vps/vps-common@${ZZ_SETUP_REF:-main}"
    common="$(command -v vps-common)"
fi
# shellcheck disable=SC1090
. "$common"

up() {
    local domain

    zz-log i "[vps-setup] Upgrading existing packages..."
    apt-get update -y
    apt-get upgrade -y

    zz-log i "[vps-setup] Installing base utilities..."
    zz-install -m \
        ca-certificates \
        curl \
        wget \
        gnupg \
        lsb-release \
        apt-transport-https \
        software-properties-common \
        git \
        jq \
        unzip \
        htop \
        net-tools \
        unattended-upgrades

    zz-log i "[vps-setup] Enabling unattended security upgrades..."
    dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null 2>&1 || true
    zz-persist -l -f /etc/apt/apt.conf.d/50unattended-upgrades-local 'Unattended-Upgrade::Automatic-Reboot "false";'
    cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

    if [ -n "${TZ:-}" ]; then
        zz-log i "[vps-setup] Setting timezone to ${TZ}..."
        timedatectl set-timezone "$TZ" || zz-log w "[vps-setup] Could not set timezone ${TZ}"
    fi

    # Wildcard DNS for apps that need subdomains; unset = nip.io, worked out where it is used.
    if [ -n "${WILDCARD_DOMAIN:-}" ]; then
        domain="${WILDCARD_DOMAIN#\*.}"
        printf '%s\n' "$domain" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$' ||
            { zz-log e "[vps-setup] WILDCARD_DOMAIN must be a bare domain like apps.example.com (got '${WILDCARD_DOMAIN}')." && exit 1; }
        zz-persist -f "$VPS_WILDCARD_FILE" WILDCARD_DOMAIN "$domain"
        zz-log i "[vps-setup] Wildcard DNS: *.${domain} (point it at this VPS)."
    else
        zz-log i "[vps-setup] No WILDCARD_DOMAIN: apps needing wildcard DNS fall back to <ip>.nip.io."
    fi

    zz-log s "[vps-setup] Base system is up to date."
}

. zz-step
