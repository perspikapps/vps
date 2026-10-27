#!/bin/sh
# Base system update and common CLI utilities.

set -eu
export DEBIAN_FRONTEND=noninteractive # apt only; ignored elsewhere
zz-use zz-colors zz-log zz-persist zz-install systemd-service
# shellcheck disable=SC1091
. zz-colors

up() {
    zz-log i "Upgrading existing packages and installing base utilities..."
    zz-install -f -m ca-certificates curl wget git jq unzip htop net-tools
    # Same tools, named differently outside Debian (gnupg2 on Amazon Linux, gpg2 on SUSE).
    zz-install -m gnupg dnf=gnupg2 zypper=gpg2

    zz-log i "Enabling unattended security upgrades..."
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
        systemd-service up dnf-automatic.timer
    else
        zz-log w "No unattended security upgrades on this distribution: run 'zypper patch' on your own schedule."
    fi

    if [ -n "${SYSTEM_TZ:-}" ]; then
        zz-log i "Setting timezone to ${SYSTEM_TZ}..."
        timedatectl set-timezone "$SYSTEM_TZ" || zz-log w "Could not set timezone ${SYSTEM_TZ}"
    fi

    zz-log s "Base system is up to date."
}

case "${1:-}" in
    up | down) "$1" ;;
    summary) if command -v summary >/dev/null 2>&1; then summary; fi ;;
    *) zz-log e "Usage: $0 up|down|summary" && exit 1 ;;
esac
