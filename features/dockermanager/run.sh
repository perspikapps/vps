#!/usr/bin/env bash
# Installs extra Cockpit modules (cockpit-packagekit for software updates,
# cockpit-files for a file browser) plus the third-party cockpit-dockermanager
# plugin (https://github.com/chrisjbawden/cockpit-dockermanager), which adds
# a Docker container/image management tab to Cockpit.
#
# cockpit-dockermanager needs an actual Docker daemon to talk to - this repo
# otherwise only sets up containerd via k3s (features/k3s/run.sh), so this
# script also installs docker.io unless INSTALL_DOCKER=false.
#
# Env vars:
#   INSTALL_DOCKER                  - "true" (default) to install docker.io
#                                     if no docker daemon is present already.
#   COCKPIT_DOCKERMANAGER_VERSION   - release tag to install (default:
#                                     "latest", the repo's rolling release
#                                     tag). Pin a specific tag, e.g. "v1.0.8.2",
#                                     to avoid picking up unexpected updates.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../lib/common.sh"

up() {
require_root
apt_update_once

log "Installing cockpit-packagekit and cockpit-files..."
apt_install cockpit-packagekit cockpit-files

INSTALL_DOCKER="${INSTALL_DOCKER:-true}"
if command_exists docker; then
  log "Docker already installed ($(docker --version))."
elif [[ "$INSTALL_DOCKER" == "true" ]]; then
  log "Installing Docker (docker.io) for cockpit-dockermanager to manage..."
  apt_install docker.io
  systemctl enable --now docker
else
  warn "Docker not installed and INSTALL_DOCKER=false; cockpit-dockermanager" \
       "will have nothing to manage until you install Docker yourself."
fi

# Let the Cockpit admin account talk to the Docker socket without sudo.
DOCKER_USER="${VPS_ADMIN_USER:-root}"
if command_exists docker && id "$DOCKER_USER" >/dev/null 2>&1 && [[ "$DOCKER_USER" != "root" ]]; then
  usermod -aG docker "$DOCKER_USER"
  log "Added ${DOCKER_USER} to the docker group (takes effect on next login)."
fi

COCKPIT_DOCKERMANAGER_VERSION="${COCKPIT_DOCKERMANAGER_VERSION:-latest}"
log "Installing cockpit-dockermanager (${COCKPIT_DOCKERMANAGER_VERSION})..."
DEB_URL="https://github.com/chrisjbawden/cockpit-dockermanager/releases/download/${COCKPIT_DOCKERMANAGER_VERSION}/dockermanager.deb"
TMP_DEB="$(mktemp --suffix=.deb)"
trap 'rm -f "$TMP_DEB"' EXIT
retry curl -fsSL "$DEB_URL" -o "$TMP_DEB"
apt-get install -y "$TMP_DEB"

systemctl try-restart cockpit.socket 2>/dev/null || true

ok "cockpit-packagekit, cockpit-files, and cockpit-dockermanager installed."
}

# Removes cockpit-dockermanager and the extra Cockpit modules installed by
# up(). Leaves the Docker daemon installed by default (other things may use
# it) - set REMOVE_DOCKER=true to also purge docker.io.
down() {
  require_root
  log "Removing cockpit-dockermanager..."
  apt-get purge -y dockermanager 2>/dev/null || warn "cockpit-dockermanager package not found (already removed?)."
  log "Removing cockpit-packagekit and cockpit-files..."
  apt-get purge -y cockpit-packagekit cockpit-files 2>/dev/null || true
  systemctl try-restart cockpit.socket 2>/dev/null || true
  if [[ "${REMOVE_DOCKER:-false}" == "true" ]] && command_exists docker; then
    log "Removing Docker (REMOVE_DOCKER=true)..."
    systemctl disable --now docker 2>/dev/null || true
    apt-get purge -y docker.io 2>/dev/null || true
  fi
  ok "cockpit-dockermanager and its extra Cockpit modules removed."
}

dispatch_action "$@"
