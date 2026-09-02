#!/bin/sh
#
# One-line VPS bootstrapper for a fresh Ubuntu install.
#
#   curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/dispatch.sh | sudo sh
#
# See README.md for the full flag/env var reference.

set -eu

REPO_URL="${VPS_SETUP_REPO_URL:-https://github.com/perspikapps/vps.git}"
REPO_REF="${VPS_SETUP_REPO_REF:-main}"
INSTALL_DIR="${VPS_SETUP_DIR:-/opt/vps-setup}"

log() { printf '\033[0;34m[vps-setup]\033[0m %s\n' "$*"; }
ok() { printf '\033[0;32m[vps-setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[vps-setup]\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[0;31m[vps-setup]\033[0m %s\n' "$*" >&2
  exit 1
}

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

if [ -f "$SCRIPT_DIR/common/run.sh" ]; then
  REPO_ROOT="$SCRIPT_DIR"
else
  if [ "$(id -u)" -ne 0 ]; then
    die "This script must be run as root (use sudo)."
  fi
  log "repo=${REPO_URL} ref=${REPO_REF} dir=${INSTALL_DIR}"
  if [ -z "${VPS_SETUP_REPO_REF:-}" ] && [ "$REPO_REF" = "main" ]; then
    warn "(VPS_SETUP_REPO_REF not set - using 'main'. Note: a plain" \
      "shell 'export' before '| sudo sh' is dropped by sudo;" \
      "set it on the sudo line instead, e.g. 'sudo VPS_SETUP_REPO_REF=... sh'.)"
  fi
  if [ -d "$INSTALL_DIR/.git" ]; then
    log "Updating existing checkout in $INSTALL_DIR..."
    git -C "$INSTALL_DIR" fetch --depth 1 origin "$REPO_REF"
    git -C "$INSTALL_DIR" checkout -q -B "$REPO_REF" FETCH_HEAD
    git -C "$INSTALL_DIR" reset --hard FETCH_HEAD
  elif [ -d "$INSTALL_DIR" ]; then
    log "$INSTALL_DIR exists and is not a git checkout; running features in place."
  else
    log "Cloning $REPO_URL (ref: $REPO_REF) into $INSTALL_DIR..."
    command -v git >/dev/null 2>&1 || (apt-get update -y && apt-get install -y --no-install-recommends git)
    git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$INSTALL_DIR"
  fi
  exec sh "$INSTALL_DIR/dispatch.sh" "$@"
fi

FEATURES_DIR="$REPO_ROOT"
cd "$REPO_ROOT"

if [ ! -r /etc/os-release ]; then
  die "Cannot detect OS: /etc/os-release missing."
fi
# shellcheck disable=SC1091
. /etc/os-release
if [ "${ID:-}" != "ubuntu" ]; then
  die "This script targets Ubuntu only (detected: ${ID:-unknown})."
fi

# --- package.json reading, via jq. Installed on demand (see ensure_jq)
# rather than assumed present, since this runs before system (the
# step that would otherwise install it) on a totally fresh box.

ensure_jq() {
  command -v jq >/dev/null 2>&1 && return 0
  if [ "$(id -u)" -ne 0 ]; then
    die "jq is required to read each feature's package.json but isn't installed, and this script isn't running as root to install it. Install it yourself (apt-get install -y jq) or re-run with sudo."
  fi
  log "Installing jq (used to read each feature's package.json)..."
  apt-get update -y >/dev/null
  apt-get install -y --no-install-recommends jq >/dev/null
}
ensure_jq

pkg_input_names() {
  # $1=file -> env var names (one per line), the keys of "vps.inputs" -
  # same shape as a GitHub composite action's "inputs:", except each key IS
  # the env var name run.sh reads.
  jq -r '(.vps.inputs // {}) | keys[]' "$1"
}

pkg_input_description() { jq -r --arg n "$2" '.vps.inputs[$n].description // empty' "$1"; }
pkg_input_required() { jq -r --arg n "$2" '.vps.inputs[$n].required // false' "$1"; }
pkg_input_default() { jq -r --arg n "$2" '.vps.inputs[$n].default // empty' "$1"; }

# --- feature discovery: <name>/{package.json,run.sh}, in install
# order - each package.json's "vps.order" (a plain integer) says where it
# falls, since folder names carry no ordering of their own.
command -v zz_use >/dev/null 2>&1 || exec sh "$REPO_ROOT/setup.sh" "$@"
list_feature_dirs() {
  for d in "$FEATURES_DIR"/*/; do
    case "$(basename "${d%/}")" in
    common | summary) continue ;;
    esac
    if [ -f "${d}package.json" ] && [ -f "${d}run.sh" ]; then
      printf '%s\t%s\n' "$(jq -r '.vps.order' "${d}package.json")" "${d%/}"
    fi
  done | sort -n -k1,1 | cut -f2-
}

feature_name() { jq -r '.name | sub("^@tomgrv/vps-"; "")' "$1/package.json"; }
feature_desc() { jq -r '.description' "$1/package.json"; }
feature_default() { jq -r '.vps.default' "$1/package.json"; }
feature_deps() { jq -r '(.dependencies // {}) | keys[] | select(startswith("@tomgrv/vps-")) | sub("^@tomgrv/vps-"; "")' "$1/package.json" | grep -vxE 'common|summary'; }
feature_inputs() { pkg_input_names "$1/package.json"; }

feature_dir_for_name() {
  for d in $(list_feature_dirs); do
    [ "$(feature_name "$d")" = "$1" ] && printf '%s\n' "$d" && return 0
  done
  return 1
}

feature_exists() { feature_dir_for_name "$1" >/dev/null 2>&1; }

ALL_NAMES=""
for d in $(list_feature_dirs); do
  ALL_NAMES="$ALL_NAMES $(feature_name "$d")"
done

# set/ask/run - see summary/dispatch-steps.sh's own header comment.
# shellcheck disable=SC1091
. "$REPO_ROOT/summary/dispatch-steps.sh"

for name in $ALL_NAMES; do
  d=$(feature_dir_for_name "$name")
  if [ "$(feature_default "$d")" = "true" ]; then
    state_set "$name" up
  else
    state_set "$name" skip
  fi
done

FORCE_DOWN=0

usage() {
  echo "Usage: dispatch.sh [options]"
  echo "       dispatch.sh                 (no options, on a terminal: interactive menu)"
  echo
  echo "Options:"
  for name in $ALL_NAMES; do
    d=$(feature_dir_for_name "$name")
    printf '  --skip-%-14s Skip %s (%s/)\n' "$name" "$(feature_desc "$d")" "$(basename "$d")"
  done
  echo
  for name in $ALL_NAMES; do
    d=$(feature_dir_for_name "$name")
    [ "$(feature_default "$d")" = "false" ] && printf '  --with-%-14s Enable %s (%s/) - opt-in, off by default\n' "$name" "$(feature_desc "$d")" "$(basename "$d")"
  done
  echo
  for name in $ALL_NAMES; do
    d=$(feature_dir_for_name "$name")
    printf '  --only-%-14s Run ONLY %s (%s/)\n' "$name" "$(feature_desc "$d")" "$(basename "$d")"
  done
  echo "                        (repeat --only-* to run more than one step; any"
  echo "                        --only-* flag overrides all --skip-*/--with-* flags)"
  echo
  for name in $ALL_NAMES; do
    d=$(feature_dir_for_name "$name")
    printf '  --down-%-14s Uninstall/disable %s (%s/) instead of installing it\n' "$name" "$(feature_desc "$d")" "$(basename "$d")"
  done
  cat <<EOF
                        (repeat --down-* to remove more than one step in the
                        same run; refused if another enabled step still
                        depends on it - see --force-down)

  --force-down           Allow --down-<step> even if a dependent step is
                        still enabled (may leave that dependent step broken)
  -h, --help            Show this help

Off-by-default steps:$(for n in $ALL_NAMES; do d=$(feature_dir_for_name "$n"); [ "$(feature_default "$d")" = "false" ] && printf ' %s' "$n"; done)
(pass --with-<step>, or --only-<step>, to run one of these).

Dependencies:$(for n in $ALL_NAMES; do d=$(feature_dir_for_name "$n"); deps=$(feature_deps "$d" | tr '\n' ' '); [ -n "$deps" ] && printf ' %s needs %s;' "$n" "$deps"; done)
(enabling a step auto-enables what it needs; --down-<step> is refused while
a dependent step is still enabled).

Every feature lives in its own workspace package: <name>/
(package.json declares its default/dependencies, run.sh is its up()/down()
script). See README.md's "Key environment variables" section for the full
env var list (each feature's package.json for ports specifically).
EOF
}

run_menu() {
  while true; do
    echo
    echo "==== VPS setup menu ===="
    i=1
    MENU_NAMES=""
    for name in $ALL_NAMES; do
      d=$(feature_dir_for_name "$name")
      marker="   "
      [ "$(feature_default "$d")" = "true" ] && marker=" * "
      printf '  %2d)%s%-14s [%-4s] %s\n' "$i" "$marker" "$name" "$(state_get "$name")" "$(feature_desc "$d")"
      MENU_NAMES="$MENU_NAMES $name"
      i=$((i + 1))
    done
    echo "  (* = installed by default) Enter a number to cycle"
    echo "  skip -> up -> down -> skip for that step."
    echo "  <enter> to proceed, 'q' to quit without changing anything."
    printf '> '
    read -r choice

    case "$choice" in
      "") break ;;
      q | Q)
        echo "Aborted, nothing changed."
        exit 0
        ;;
      *[!0-9]*)
        echo "Invalid input: '$choice' (enter a number, or press enter/q)."
        continue
        ;;
    esac

    name=$(echo "$MENU_NAMES" | tr ' ' '\n' | sed -n "$((choice + 1))p")
    if [ -z "$name" ]; then
      echo "No such step: $choice"
      continue
    fi
    case "$(state_get "$name")" in
      skip) state_set "$name" up ;;
      up) state_set "$name" down ;;
      down) state_set "$name" skip ;;
    esac
  done
}

ONLY_LIST=""
for arg in "$@"; do
  case "$arg" in
    --skip-*)
      name=${arg#--skip-}
      if feature_exists "$name"; then
        state_set "$name" skip
      else
        echo "Unknown option: $arg" >&2
        usage
        exit 1
      fi
      ;;
    --with-*)
      name=${arg#--with-}
      if feature_exists "$name"; then
        state_set "$name" up
      else
        echo "Unknown option: $arg" >&2
        usage
        exit 1
      fi
      ;;
    --only-*)
      name=${arg#--only-}
      if feature_exists "$name"; then
        ONLY_LIST="$ONLY_LIST $name"
      else
        echo "Unknown option: $arg" >&2
        usage
        exit 1
      fi
      ;;
    --down-*)
      name=${arg#--down-}
      if feature_exists "$name"; then
        state_set "$name" down
      else
        echo "Unknown option: $arg" >&2
        usage
        exit 1
      fi
      ;;
    --force-down) FORCE_DOWN=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      usage
      exit 1
      ;;
  esac
done

if [ "$#" -eq 0 ] && [ -t 0 ]; then
  run_menu
fi

if [ -n "$ONLY_LIST" ]; then
  for name in $ALL_NAMES; do state_set "$name" skip; done
  for name in $ONLY_LIST; do state_set "$name" up; done
fi

pass=0
while [ "$pass" -lt 3 ]; do
  changed=0
  for name in $ALL_NAMES; do
    [ "$(state_get "$name")" = "up" ] || continue
    d=$(feature_dir_for_name "$name")
    for dep in $(feature_deps "$d"); do
      if [ "$(state_get "$dep")" = "skip" ]; then
        warn "Also enabling '${dep}' (required by '${name}')."
        state_set "$dep" up
        changed=1
      fi
    done
  done
  [ "$changed" -eq 0 ] && break
  pass=$((pass + 1))
done

if [ "$FORCE_DOWN" -ne 1 ]; then
  for name in $ALL_NAMES; do
    [ "$(state_get "$name")" = "down" ] || continue
    for other in $ALL_NAMES; do
      [ "$other" = "$name" ] && continue
      [ "$(state_get "$other")" = "up" ] || continue
      d=$(feature_dir_for_name "$other")
      for dep in $(feature_deps "$d"); do
        if [ "$dep" = "$name" ]; then
          die "Refusing to bring '${name}' down: '${other}' depends on it and is still enabled. Also pass --down-${other}, or --force-down to override (may leave '${other}' broken)."
        fi
      done
    done
  done
fi

if [ "$(id -u)" -ne 0 ]; then
  die "This script must be run as root (use sudo)."
fi

# Ask for any input every enabled ("up") step declares that isn't already
# set in the environment - see summary/dispatch-steps.sh's ask_missing_inputs.
ask_missing_inputs

# ufw (security) only opens this repo's Tailscale-only services
# (see this feature's own package.json) to the tailscale0 interface, so running the rest of
# the install without Tailscale authenticated would leave all of them
# unreachable. Refuse to proceed rather than silently produce a VPS
# nothing can be managed on.
if [ "$(state_get tailscale)" = "up" ] && [ -z "${TAILSCALE_AUTHKEY:-}" ]; then
  warn "TAILSCALE_AUTHKEY is not set, but the tailscale step is enabled." \
    "Cockpit, Rancher, ArgoCD, the Traefik dashboard, and the k3s API" \
    "are reachable ONLY over Tailscale (see README's Security model) -" \
    "continuing without it would leave all of them unreachable once ufw" \
    "locks the box down. Either:" \
    "  - set TAILSCALE_AUTHKEY (see README's 'Getting the keys you'll need'), or" \
    "  - pass --skip-tailscale to proceed anyway (you can run 'tailscale up'" \
    "    manually later, then: sudo sh dispatch.sh --only-tailscale)."
  die "Refusing to run with tailscale enabled and TAILSCALE_AUTHKEY unset."
fi

# Tear down requested steps first (in reverse order, so dependents come
# down before what they depend on), then install/reconcile everything
# still enabled.
for name in $(echo "$ALL_NAMES" | tr ' ' '\n' | sed '1!G;h;$!d' | tr '\n' ' '); do
  [ "$(state_get "$name")" = "down" ] && run_step "$name" down
done

for name in $ALL_NAMES; do
  case "$(state_get "$name")" in
    up) run_step "$name" up ;;
    *)
      d=$(feature_dir_for_name "$name")
      warn "Skipping $(feature_desc "$d") ($(basename "$d")/run.sh)"
      ;;
  esac
done

bash "$REPO_ROOT/summary/run.sh"
