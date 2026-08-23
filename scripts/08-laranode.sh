#!/usr/bin/env bash
# Installs Laranode (https://laranode.com), an open-source Laravel/LAMP
# hosting control panel, via its official one-line installer. Unlike
# everything else in this repo, Laranode has no container image or Helm
# chart upstream - it's a traditional VPS panel that installs its own
# Apache/MySQL/PHP-FPM stack directly on the host and manages its own
# systemd services, so it's installed natively here rather than into k3s.
#
# Laranode's installer opens ufw for 80, 443, and 8080 (its Reverb
# websocket service) PUBLICLY - unlike the rest of this repo's
# Tailscale-only default, and left that way here on purpose: Laranode's
# whole point is hosting public-facing websites (and its "one-click Let's
# Encrypt" feature needs port 80 reachable from the public internet for
# ACME HTTP-01 validation), so restricting it to Tailscale by default
# would defeat its own core purpose. Set LARANODE_TAILSCALE_ONLY=true if
# you specifically want it private instead (e.g. an internal-only panel).
#
# NOTE: Laranode hardcodes port 8080 for Reverb, which collides with this
# repo's own RANCHER_HTTP_PORT default (also 8080) if you install both -
# set RANCHER_HTTP_PORT to something else first if so.
#
# WORKAROUND: laranode-installer.sh adds `ppa:ondrej/php` and installs
# php8.4 from it, but that PPA lags new Ubuntu releases by months (e.g. it
# 404s outright on 26.04/"resolute" - Launchpad's own page for it names
# https://packages.sury.org/php/ as the replacement for that case). Worse,
# the installer has `# set -e` commented out, so when that apt step fails
# it doesn't stop - it carries on straight into `composer install` and
# `php artisan ...` with no PHP installed at all, failing "command not
# found" on every one of them and leaving a broken, half-built install
# (cloned repo, npm/vite assets built, ufw rules added, but no
# vendor/.env/migrations). This script pre-installs PHP 8.4 + Composer
# from Sury's repo before handing off to the installer, so its own
# ppa:ondrej/php + apt-install step becomes a no-op (packages already
# satisfied) regardless of whether that PPA supports the running release.
#
# Env vars:
#   LARANODE_TAILSCALE_ONLY - "true" to restrict Laranode's ports
#                             (80/443/8080) to Tailscale instead of
#                             leaving them public (default: false - see
#                             note above on why public is the default)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

require_root
apt_update_once

LARANODE_TAILSCALE_ONLY="${LARANODE_TAILSCALE_ONLY:-false}"

if [[ "${RANCHER_HTTP_PORT:-8080}" == "8080" ]]; then
  warn "Laranode's Reverb websocket service hardcodes port 8080, the same" \
       "as this repo's default RANCHER_HTTP_PORT. If you're installing" \
       "both, set RANCHER_HTTP_PORT to something else before running" \
       "scripts/06-rancher.sh."
fi

# Only re-run the installer if it hasn't fully succeeded before: check for
# the systemd units it creates AND the app's vendor/ dir (composer
# install's output) - a systemd unit alone can exist from a run that died
# partway through (exactly the failure mode this script works around),
# which would otherwise make this look "done" forever.
LARANODE_APP_DIR="/home/laranode_ln/panel"
if systemctl list-unit-files 2>/dev/null | grep -q '^laranode' && [[ -d "${LARANODE_APP_DIR}/vendor" ]]; then
  log "Laranode already installed (systemd units + ${LARANODE_APP_DIR}/vendor present); skipping installer."
  log "Re-run its installer manually to upgrade: see https://laranode.com"
else
  if [[ -d "$LARANODE_APP_DIR" ]]; then
    warn "Found a partial/broken previous Laranode install at ${LARANODE_APP_DIR}" \
         "(no vendor/ - a previous run likely failed before 'composer install')." \
         "Removing it so the installer's 'git clone' (not idempotent) can start fresh."
    rm -rf "$LARANODE_APP_DIR"
  fi
  apt_install lsb-release ca-certificates curl gnupg
  if ! command_exists php || ! command_exists composer; then
    log "Pre-installing PHP 8.4 + Composer from Sury's repo (see WORKAROUND note above)..."
    if [[ ! -f /etc/apt/sources.list.d/php.list ]]; then
      retry curl -fsSL -o /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb
      dpkg -i /tmp/debsuryorg-archive-keyring.deb
      rm -f /tmp/debsuryorg-archive-keyring.deb
      echo "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
      apt-get update -y
    fi
    apt_install php8.4 php8.4-fpm php8.4-cli php8.4-common php8.4-curl \
      php8.4-mbstring php8.4-xml php8.4-bcmath php8.4-zip php8.4-mysql \
      php8.4-sqlite3 php8.4-pgsql php8.4-gd php8.4-imagick php8.4-intl \
      php8.4-readline php8.4-tokenizer php8.4-fileinfo php8.4-soap \
      php8.4-opcache unzip
    command_exists php || die "PHP install failed even via Sury's repo for $(lsb_release -sc)." \
      "Laranode isn't installable on this Ubuntu release yet; try 22.04 or 24.04."
    if ! command_exists composer; then
      retry curl -sS https://getcomposer.org/installer -o /tmp/composer-installer.php
      php /tmp/composer-installer.php --install-dir=/usr/local/bin --filename=composer
      rm -f /tmp/composer-installer.php
    fi
  fi

  log "Running the official Laranode installer..."
  retry curl -fsSL https://raw.githubusercontent.com/crivion/laranode/main/laranode-scripts/bin/laranode-installer.sh -o /tmp/laranode-installer.sh
  bash /tmp/laranode-installer.sh
  rm -f /tmp/laranode-installer.sh
  [[ -d "${LARANODE_APP_DIR}/vendor" ]] || die "laranode-installer.sh finished but ${LARANODE_APP_DIR}/vendor is missing -" \
    "composer install likely failed silently (the installer has no 'set -e'). Check its output above."
  ok "Laranode installer finished - credentials it printed above are shown only once, save them now."
fi

if [[ "$LARANODE_TAILSCALE_ONLY" == "true" ]]; then
  log "LARANODE_TAILSCALE_ONLY=true: restricting Laranode's ports (80/443/8080) to Tailscale..."
  warn "This also disables Laranode's own Let's Encrypt issuance (ACME" \
       "HTTP-01 needs port 80 reachable from the public internet)."
  for port in 80 443 8080; do
    ufw delete allow "${port}/tcp" >/dev/null 2>&1 || true
    ufw allow in on tailscale0 to any port "$port" proto tcp comment "vps-setup: tailscale-only (laranode)" || true
  done
  ufw reload >/dev/null 2>&1 || true
  ok "Laranode restricted to Tailscale."
else
  ok "Laranode left public on 80/443/8080 (its installer's own ufw rules), so its hosted" \
     "sites and Let's Encrypt issuance work as intended. Set LARANODE_TAILSCALE_ONLY=true" \
     "to restrict it to Tailscale instead."
fi
