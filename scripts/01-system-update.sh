#!/usr/bin/env bash
# Base system update and the small toolset every later script assumes exists.
# Equivalent in spirit to devcontainers/features "common-utils": update apt,
# set a sane locale/timezone, install common CLI utilities, non-interactively.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

require_root
apt_update_once
log "Upgrading existing packages..."
apt-get upgrade -y

log "Installing base utilities..."
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

log "Enabling unattended security upgrades..."
dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null 2>&1 || true
ensure_line 'Unattended-Upgrade::Automatic-Reboot "false";' /etc/apt/apt.conf.d/50unattended-upgrades-local
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

if [[ -n "${TZ:-}" ]]; then
  log "Setting timezone to ${TZ}..."
  timedatectl set-timezone "$TZ" || warn "Could not set timezone ${TZ}"
fi

ok "Base system is up to date."
