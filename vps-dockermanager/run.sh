#!/usr/bin/env bash
# cockpit-packagekit, cockpit-files, cockpit-dockermanager. Env vars: see README.

set -euo pipefail
command -v zz_use >/dev/null 2>&1 || { echo "zz_use not found on PATH - run this repo's setup.sh first: curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/setup.sh | sh" >&2; exit 1; }
zz_use "perspikapps/vps/vps-common@${VPS_SETUP_REPO_REF:-main}"
# shellcheck disable=SC1091
. vps-common

up() {
require_root
apt_update_once

zz_log i "[vps-setup] Installing cockpit-packagekit and cockpit-files..."
apt_install cockpit-packagekit cockpit-files

INSTALL_DOCKER="${INSTALL_DOCKER:-true}"
if command_exists docker; then
  zz_log i "[vps-setup] Docker already installed ($(docker --version))."
elif [[ "$INSTALL_DOCKER" == "true" ]]; then
  zz_log i "[vps-setup] Installing Docker (docker.io) for cockpit-dockermanager to manage..."
  apt_install docker.io
  systemctl enable --now docker
else
  zz_log w "[vps-setup] Docker not installed and INSTALL_DOCKER=false; cockpit-dockermanager" \
       "will have nothing to manage until you install Docker yourself."
fi

DOCKER_USER="${VPS_ADMIN_USER:-root}"
if command_exists docker && id "$DOCKER_USER" >/dev/null 2>&1 && [[ "$DOCKER_USER" != "root" ]]; then
  usermod -aG docker "$DOCKER_USER"
  zz_log i "[vps-setup] Added ${DOCKER_USER} to the docker group (takes effect on next login)."
fi

COCKPIT_DOCKERMANAGER_VERSION="${COCKPIT_DOCKERMANAGER_VERSION:-latest}"
zz_log i "[vps-setup] Installing cockpit-dockermanager (${COCKPIT_DOCKERMANAGER_VERSION})..."
DEB_URL="https://github.com/chrisjbawden/cockpit-dockermanager/releases/download/${COCKPIT_DOCKERMANAGER_VERSION}/dockermanager.deb"
TMP_DEB="$(mktemp --suffix=.deb)"
trap 'rm -f "$TMP_DEB"' EXIT
retry curl -fsSL "$DEB_URL" -o "$TMP_DEB"
apt-get install -y "$TMP_DEB"

systemctl try-restart cockpit.socket 2>/dev/null || true

ok "cockpit-packagekit, cockpit-files, and cockpit-dockermanager installed."
}

down() {
  require_root
  zz_log i "[vps-setup] Removing cockpit-dockermanager..."
  apt-get purge -y dockermanager 2>/dev/null || zz_log w "[vps-setup] cockpit-dockermanager package not found (already removed?)."
  zz_log i "[vps-setup] Removing cockpit-packagekit and cockpit-files..."
  apt-get purge -y cockpit-packagekit cockpit-files 2>/dev/null || true
  systemctl try-restart cockpit.socket 2>/dev/null || true
  if [[ "${REMOVE_DOCKER:-false}" == "true" ]] && command_exists docker; then
    zz_log i "[vps-setup] Removing Docker (REMOVE_DOCKER=true)..."
    systemctl disable --now docker 2>/dev/null || true
    apt-get purge -y docker.io 2>/dev/null || true
  fi
  ok "cockpit-dockermanager and its extra Cockpit modules removed."
}

dispatch_action "$@"
