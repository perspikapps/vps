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
# WORKAROUND (PHP): laranode-installer.sh adds `ppa:ondrej/php` and
# installs php8.4 from it, but that PPA lags new Ubuntu releases by months
# (e.g. it 404s outright on 26.04/"resolute"). Sury's repo
# (https://packages.sury.org/php/, the PPA's own recommended replacement)
# can lag too - as of this writing it also has no "resolute" packages.
# Worse, the installer has `# set -e` commented out, so when the apt step
# fails it doesn't stop - it carries on straight into `composer install`
# and `php artisan ...` with no PHP installed at all, failing "command not
# found" on every one of them and leaving a broken, half-built install
# (cloned repo, npm/vite assets built, ufw rules added, but no
# vendor/.env/migrations). This script pre-installs PHP 8.4 + Composer
# from Sury before handing off to the installer, trying the host's own
# codename first and falling back to Ubuntu 24.04's ("noble") packages if
# Sury doesn't support the running release yet - PHP userspace packages
# are ABI/glibc-compatible across adjacent Ubuntu releases, so this is a
# well-known, widely-used workaround for exactly this situation. Either
# way, Laranode's own ppa:ondrej/php + apt-install step then becomes a
# harmless no-op since the packages are already satisfied.
#
# WORKAROUND (sudoers): laranode-installer.sh also writes a sudoers rule
# with a wildcard inside a command ARGUMENT (`/bin/rm
# .../sites-available/*.conf`) - sudo's parser only permits wildcards in
# the command path, never in arguments, so this specific clause is
# permanently invalid on any system/version and sudo silently skips it
# (with a recurring "wildcards are not allowed in command arguments"
# warning every time the file is parsed). That permission was never
# actually granted in the first place, so this script removes just that
# clause - verified safe with `visudo -c` before applying, and leaving it
# untouched if that check fails.
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

# WORKAROUND (apt): laranode-installer.sh runs `add-apt-repository -y
# ppa:ondrej/php` unconditionally (every time it's invoked, including the
# runs below), which on an unsupported release (see WORKAROUND (PHP)
# below) leaves behind a source file with no valid Release - and
# `apt-get update` returns nonzero if ANY configured source fails, not
# just the broken one, so that leftover breaks every apt operation on
# this box afterwards, not just Laranode's, until removed. Called both
# before touching apt ourselves (in case a previous run left it behind)
# and after invoking the installer (since it re-adds it every time).
clean_broken_ondrej_php_source() {
  local f
  for f in /etc/apt/sources.list.d/*ondrej*php*; do
    [[ -f "$f" ]] || continue
    if grep -q 'ppa\.launchpadcontent\.net/ondrej/php' "$f" 2>/dev/null; then
      warn "Removing a broken ppa:ondrej/php source (${f}) - it doesn't support" \
           "$(lsb_release -sc 2>/dev/null || echo "this release") and would block all" \
           "apt operations on this box otherwise."
      rm -f "$f"
    fi
  done
}

clean_broken_ondrej_php_source
apt_update_once

# See WORKAROUND (sudoers) note above. Idempotent: a no-op once the clause
# is gone. Never touches /etc/sudoers unless the corrected copy validates
# cleanly with `visudo -c` first.
fix_laranode_sudoers() {
  local sudoers=/etc/sudoers
  local broken=', /bin/rm /etc/apache2/sites-available/*.conf'
  [[ -f "$sudoers" ]] || return 0
  grep -qF "$broken" "$sudoers" 2>/dev/null || return 0
  log "Removing Laranode's invalid sudoers clause (wildcard in a command argument - sudo" \
      "always rejects this and already silently skips it; this permission was never granted)..."
  local tmp
  tmp="$(mktemp)"
  local escaped
  escaped="$(printf '%s' "$broken" | sed -e 's/[.[\*^$/\\]/\\&/g')"
  sed "s/${escaped}//" "$sudoers" > "$tmp"
  if visudo -c -f "$tmp" >/dev/null 2>&1; then
    install -m 0440 -o root -g root "$tmp" "$sudoers"
    ok "Fixed: removed the invalid clause, validated with visudo -c before applying."
  else
    warn "Could not safely fix the sudoers clause (the corrected file failed visudo -c) -" \
         "leaving /etc/sudoers untouched. This permission was already non-functional before," \
         "so nothing is newly broken."
  fi
  rm -f "$tmp"
}

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
  fix_laranode_sudoers
else
  if [[ -d "$LARANODE_APP_DIR" ]]; then
    warn "Found a partial/broken previous Laranode install at ${LARANODE_APP_DIR}" \
         "(no vendor/ - a previous run likely failed before 'composer install')." \
         "Removing it so the installer's 'git clone' (not idempotent) can start fresh."
    rm -rf "$LARANODE_APP_DIR"
  fi

  # WORKAROUND (apache): the installer restarts apache2 early in its run -
  # before (re-)cloning the app - so if an enabled vhost from a PREVIOUS
  # run still points at ${LARANODE_APP_DIR} (whether removed just above or
  # already gone from an earlier attempt), apache2 fails to start outright
  # (it can't open the vhost's error log in a directory that doesn't
  # exist), which breaks everything after it in the same run. Checked
  # against whether the directory exists *right now*, not just whether
  # this run removed it, since it may already have been missing coming
  # in. Laranode's own installer recreates this vhost correctly once the
  # app is (re-)cloned, so it's safe to just disable the stale one now.
  if [[ ! -d "$LARANODE_APP_DIR" && -f /etc/apache2/sites-enabled/000-default.conf ]] && \
     grep -qF "$LARANODE_APP_DIR" /etc/apache2/sites-enabled/000-default.conf 2>/dev/null; then
    warn "Disabling a stale Apache vhost pointing at a Laranode directory that no longer" \
         "exists, so apache2 can start again before the installer recreates it."
    a2dissite 000-default >/dev/null 2>&1 || rm -f /etc/apache2/sites-enabled/000-default.conf
  fi
  apt_install lsb-release ca-certificates curl gnupg
  if ! command_exists php || ! command_exists composer; then
    log "Pre-installing PHP 8.4 + Composer from Sury's repo (see WORKAROUND note above)..."
    if [[ ! -f /usr/share/keyrings/debsuryorg-archive-keyring.gpg ]]; then
      retry curl -fsSL -o /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb
      dpkg -i /tmp/debsuryorg-archive-keyring.deb
      rm -f /tmp/debsuryorg-archive-keyring.deb
    fi

    NATIVE_CODENAME="$(lsb_release -sc)"
    PHP_CODENAME=""
    for codename in "$NATIVE_CODENAME" noble; do
      echo "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ ${codename} main" > /etc/apt/sources.list.d/php.list
      apt-get update -y >/dev/null 2>&1 || true
      if apt-cache show php8.4 >/dev/null 2>&1; then
        PHP_CODENAME="$codename"
        break
      fi
    done

    if [[ -z "$PHP_CODENAME" ]]; then
      rm -f /etc/apt/sources.list.d/php.list
      die "PHP 8.4 isn't available from Sury's repo for ${NATIVE_CODENAME} or the noble (24.04)" \
          "fallback. Laranode isn't installable on this Ubuntu release yet; try 22.04 or 24.04."
    fi
    [[ "$PHP_CODENAME" != "$NATIVE_CODENAME" ]] && warn "${NATIVE_CODENAME} isn't supported by" \
      "Sury's repo yet - using its noble (24.04) packages instead (PHP userspace packages are" \
      "ABI-compatible across adjacent Ubuntu releases; this is a common, safe workaround)."

    apt_install php8.4 php8.4-fpm php8.4-cli php8.4-common php8.4-curl \
      php8.4-mbstring php8.4-xml php8.4-bcmath php8.4-zip php8.4-mysql \
      php8.4-sqlite3 php8.4-pgsql php8.4-gd php8.4-imagick php8.4-intl \
      php8.4-readline php8.4-tokenizer php8.4-fileinfo php8.4-soap \
      php8.4-opcache unzip
    command_exists php || die "php8.4 packages reported available but the php binary is still" \
      "missing after apt_install - check apt output above."
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
  clean_broken_ondrej_php_source
  apt-get update -y >/dev/null 2>&1 || true
  [[ -d "${LARANODE_APP_DIR}/vendor" ]] || die "laranode-installer.sh finished but ${LARANODE_APP_DIR}/vendor is missing -" \
    "composer install likely failed silently (the installer has no 'set -e'). Check its output above."
  fix_laranode_sudoers
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
