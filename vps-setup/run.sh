#!/usr/bin/env bash
# Thin wrapper around zz-setup: runs every step of this repo in order (or just
# the ones asked for) - feature discovery, the skip/up/down menu, dependency
# resolution, input prompts and persistence are zz-setup's - then prints the
# final connection summary. Installed and invoked as `vps-setup` - see
# README's "Running vps-setup" section.
#
# What stays here: the Ubuntu/root checks, the legacy --skip-<step> /
# --with-<step> / --only-<step> / --down-<step> / --force-down flags
# (translated to zz-setup's -s/-w/-o/-d/-F lists), the shell-syntax settings
# file (VPS_SETUP_ENV_FILE) and the summary.

set -euo pipefail

# Settings file written at provisioning time (cloud-init): shell syntax, so it
# is sourced here, never rewritten. zz-setup keeps its own plain-text state
# for answers typed in the menu.
ENV_FILE="${VPS_SETUP_ENV_FILE:-/etc/vps-setup.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

# --force: the steps that zz-setup runs fetch vps-common through zz-use's cache
# (24h for a branch ref, one slot per repo+ref). Refreshing it here keeps the
# helpers in step with the checkout zz-setup is about to run.
zz-use --force "perspikapps/vps/vps-common@${ZZ_SETUP_REF:-main}" zz-setup
# shellcheck disable=SC1091
. vps-common

# -h only prints zz-setup's help, which needs neither.
[[ " $* " == *" -h "* ]] || { require_root; require_ubuntu; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/../vps-common/run.sh" ]]; then
  # Full local checkout (dev clone, `bash vps-setup/run.sh`): used in place.
  CHECKOUT="$(cd "$SCRIPT_DIR/.." && pwd)"
  REPO="$CHECKOUT"
else
  # Standalone zz-use install: zz-setup fetches the whole repo into /opt/<repo>.
  REPO_URL="${VPS_SETUP_REPO_URL:-https://github.com/perspikapps/vps.git}"
  REPO_PATH="$(printf '%s' "$REPO_URL" | sed -E 's#^[A-Za-z+]+://[^/]+/##; s#\.git$##')"
  export ZZ_SETUP_URL_BASE="${REPO_URL%/"$REPO_PATH"*}"
  export ZZ_SETUP_DIR="${ZZ_SETUP_DIR:-/opt}"
  CHECKOUT="$ZZ_SETUP_DIR/${REPO_PATH##*/}"
  REPO="$REPO_PATH@${ZZ_SETUP_REF:-main}"
fi

# Legacy flags -> zz-setup lists; anything else (e.g. -h) goes through as is.
skip=() with=() only=() down=() opts=()
for arg in "$@"; do
  case "$arg" in
    --skip-*) skip+=("${arg#--skip-}") ;;
    --with-*) with+=("${arg#--with-}") ;;
    --only-*) only+=("${arg#--only-}") ;;
    --down-*) down+=("${arg#--down-}") ;;
    --force-down) opts+=(-F) ;;
    *) opts+=("$arg") ;;
  esac
done
join() { local IFS=,; printf '%s' "$*"; }
[[ ${#skip[@]} -eq 0 ]] || opts+=(-s "$(join "${skip[@]}")")
[[ ${#with[@]} -eq 0 ]] || opts+=(-w "$(join "${with[@]}")")
[[ ${#only[@]} -eq 0 ]] || opts+=(-o "$(join "${only[@]}")")
[[ ${#down[@]} -eq 0 ]] || opts+=(-d "$(join "${down[@]}")")

zz-setup "$REPO" "${opts[@]}"

# vps-common's feature_dirs reads every feature's package.json from here.
VPS_SETUP_ROOT="$CHECKOUT"

# --- summary: final connection info, printed after every run (also
# callable on its own afterwards - see README's "Running vps-setup"
# section). Each step prints its own block (its `summary` action), in
# vps.order; none of it depends on what this run just did versus a
# previous one.

cat <<'EOF'

======================================================================
 VPS setup complete
======================================================================
EOF
while IFS= read -r dir; do
  out="$(bash "$dir/run.sh" summary)" || true
  [[ -z "$out" ]] || printf '%s\n\n' "$out"
done < <(ordered_feature_dirs)
printf '======================================================================\n'
