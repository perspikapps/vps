#!/usr/bin/env bash
# Base system update and common CLI utilities.

set -euo pipefail
command -v zz_use >/dev/null 2>&1 || { echo "zz_use not found on PATH - run this repo's setup.sh first: curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/setup.sh | sh" >&2; exit 1; }
zz_use "perspikapps/vps/common@${VPS_SETUP_REPO_REF:-main}"
# shellcheck disable=SC1091
. common

up() {
  require_root
  apt_update_once
  zz_log i "[vps-setup] Upgrading existing packages..."
  apt-get upgrade -y

  zz_log i "[vps-setup] Installing base utilities..."
  apt_install \
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

  zz_log i "[vps-setup] Enabling unattended security upgrades..."
  dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null 2>&1 || true
  ensure_line 'Unattended-Upgrade::Automatic-Reboot "false";' /etc/apt/apt.conf.d/50unattended-upgrades-local
  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

  if [[ -n "${TZ:-}" ]]; then
    zz_log i "[vps-setup] Setting timezone to ${TZ}..."
    timedatectl set-timezone "$TZ" || zz_log w "[vps-setup] Could not set timezone ${TZ}"
  fi

  ok "Base system is up to date."
}

dispatch_action "$@"
