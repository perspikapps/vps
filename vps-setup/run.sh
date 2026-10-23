#!/bin/sh
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

set -eu

# --- settings file
# Written at provisioning time (cloud-init): shell syntax, so it is sourced
# here, never rewritten. zz-setup keeps its own plain-text state for answers
# typed in the menu.
env_file="${VPS_SETUP_ENV_FILE:-/etc/vps-setup.env}"
if [ -f "$env_file" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$env_file"
    set +a
fi

# --- helpers
# --force: the steps that zz-setup runs fetch vps-common through zz-use's cache
# (24h for a branch ref, one slot per repo+ref). Refreshing it here keeps the
# helpers in step with the checkout zz-setup is about to run.
zz-use --force "perspikapps/vps/vps-common@${ZZ_SETUP_REF:-main}" zz-setup
# shellcheck disable=SC1091
. vps-common

# -h only prints zz-setup's help, which needs neither.
case " $* " in
    *" -h "*) ;;
    *)
        require_root
        require_ubuntu
        ;;
esac

# --- checkout
script_dir="$(cd "$(dirname "$0")" && pwd)"

if [ -f "$script_dir/../vps-common/run.sh" ]; then
    # Full local checkout (dev clone, `sh vps-setup/run.sh`): used in place.
    checkout="$(cd "$script_dir/.." && pwd)"
    repo="$checkout"
else
    # Standalone zz-use install: zz-setup fetches the whole repo into /opt/<repo>.
    repo_url="${VPS_SETUP_REPO_URL:-https://github.com/perspikapps/vps.git}"
    repo_path="$(printf '%s' "$repo_url" | sed -E 's#^[A-Za-z+]+://[^/]+/##; s#\.git$##')"
    export ZZ_SETUP_URL_BASE="${repo_url%/"$repo_path"*}"
    export ZZ_SETUP_DIR="${ZZ_SETUP_DIR:-/opt}"
    checkout="$ZZ_SETUP_DIR/${repo_path##*/}"
    repo="$repo_path@${ZZ_SETUP_REF:-main}"
fi

# --- legacy flags
# Translated to zz-setup lists (comma-joined names); anything else (e.g. -h)
# goes through as is, in order. The arguments are rotated through "$@" so each
# keeps its quoting.
skip="" with="" only="" down=""
count=$#
while [ "$count" -gt 0 ]; do
    arg="$1"
    shift
    count=$((count - 1))
    case "$arg" in
        --skip-*) skip="${skip:+$skip,}${arg#--skip-}" ;;
        --with-*) with="${with:+$with,}${arg#--with-}" ;;
        --only-*) only="${only:+$only,}${arg#--only-}" ;;
        --down-*) down="${down:+$down,}${arg#--down-}" ;;
        --force-down) set -- "$@" -F ;;
        *) set -- "$@" "$arg" ;;
    esac
done
[ -z "$skip" ] || set -- "$@" -s "$skip"
[ -z "$with" ] || set -- "$@" -w "$with"
[ -z "$only" ] || set -- "$@" -o "$only"
[ -z "$down" ] || set -- "$@" -d "$down"

zz-setup "$repo" "$@"

# --- summary
# Final connection info, printed after every run (also callable on its own
# afterwards - see README's "Running vps-setup" section). zz-setup -m asks each
# step that declares config.summary for its block (its `summary` action), in
# config.order; none of it depends on what this run just did versus a previous one.
cat <<'EOF'

======================================================================
 VPS setup complete
======================================================================
EOF
zz-setup "$repo" -m
printf '======================================================================\n'
