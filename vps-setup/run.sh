#!/usr/bin/env bash
# Interactive/flag-driven orchestrator: runs every step in this repo in
# order (or just the ones asked for), resolving dependencies and prompting
# for missing inputs, then prints the final connection summary. Installed
# and invoked as `vps-setup` - see README's "Running vps-setup" section.
#
# Unlike every other feature here, this one isn't itself installed/removed
# via up()/down() - it drives all the others - so it doesn't end with
# dispatch_action. It's still zz_use-installable like any feature, but
# since a single zz_use fetch only pulls this one folder, it needs a full
# local checkout of every sibling feature folder to orchestrate them -
# see the REPO_ROOT resolution below.

set -euo pipefail
command -v zz_use >/dev/null 2>&1 || { echo "zz_use not found on PATH - run this repo's setup.sh first: curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/setup.sh | sh" >&2; exit 1; }
zz_use "perspikapps/vps/vps-common@${VPS_SETUP_REPO_REF:-main}"
# shellcheck disable=SC1091
. vps-common

REPO_URL="${VPS_SETUP_REPO_URL:-https://github.com/perspikapps/vps.git}"
REPO_REF="${VPS_SETUP_REPO_REF:-main}"
INSTALL_DIR="${VPS_SETUP_DIR:-/opt/vps-setup}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/../vps-common/run.sh" ]]; then
  # Running from within a full local checkout (e.g. `bash vps-setup/run.sh`
  # from the repo root, or a dev clone) - every sibling folder is already
  # right there, nothing to clone.
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  # zz_use-installed standalone: this folder alone was fetched, so every
  # sibling feature folder needs a full checkout to orchestrate them.
  require_root
  zz_log i "[vps-setup] repo=${REPO_URL} ref=${REPO_REF} dir=${INSTALL_DIR}"
  if [[ -z "${VPS_SETUP_REPO_REF:-}" ]] && [[ "$REPO_REF" == "main" ]]; then
    zz_log w "[vps-setup] (VPS_SETUP_REPO_REF not set - using 'main'. Note: a plain" \
      "shell 'export' before 'sudo vps-setup' is dropped by sudo;" \
      "set it on the sudo line instead, e.g. 'sudo VPS_SETUP_REPO_REF=... vps-setup'.)"
  fi
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    zz_log i "[vps-setup] Updating existing checkout in $INSTALL_DIR..."
    git -C "$INSTALL_DIR" fetch --depth 1 origin -- "$REPO_REF"
    git -C "$INSTALL_DIR" checkout -q -B "$REPO_REF" FETCH_HEAD
    git -C "$INSTALL_DIR" reset --hard FETCH_HEAD
  elif [[ -d "$INSTALL_DIR" ]]; then
    zz_log i "[vps-setup] $INSTALL_DIR exists and is not a git checkout; running features in place."
  else
    zz_log i "[vps-setup] Cloning $REPO_URL (ref: $REPO_REF) into $INSTALL_DIR..."
    if ! command_exists git; then
      apt_update_once
      apt_install git
    fi
    git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$INSTALL_DIR"
  fi
  REPO_ROOT="$INSTALL_DIR"
fi

FEATURES_DIR="$REPO_ROOT"
cd "$REPO_ROOT"

if [[ ! -r /etc/os-release ]]; then
  zz_log e "[vps-setup] Cannot detect OS: /etc/os-release missing."
  exit 1
fi
# shellcheck disable=SC1091
. /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  zz_log e "[vps-setup] This script targets Ubuntu only (detected: ${ID:-unknown})."
  exit 1
fi

# --- package.json reading, via jq. Installed on demand rather than
# assumed present, since this can run before vps-system (the step that
# would otherwise install it) on a totally fresh box.
ensure_jq() {
  command_exists jq && return 0
  require_root
  zz_log i "[vps-setup] Installing jq (used to read each feature's package.json)..."
  apt_update_once
  apt_install jq
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
list_feature_dirs() {
  for d in "$FEATURES_DIR"/*/; do
    case "$(basename "${d%/}")" in
    vps-common | vps-setup) continue ;;
    esac
    if [[ -f "${d}package.json" ]] && [[ -f "${d}run.sh" ]]; then
      printf '%s\t%s\n' "$(jq -r '.vps.order' "${d}package.json")" "${d%/}"
    fi
  done | sort -n -k1,1 | cut -f2-
}

# CLI/state identity is the package.json "name" with only the npm scope
# stripped ("@tomgrv/vps-rancher" -> "vps-rancher") - same as the folder
# name, since folder names match workspace names (see README's "One
# folder per feature"). No further "vps-" stripping: every folder and
# every --skip-<x>/--only-<x>/--down-<x> flag carries it uniformly, same
# as this repo's own package scope.
feature_name() { jq -r '.name | sub("^@tomgrv/"; "")' "$1/package.json"; }
feature_desc() { jq -r '.description' "$1/package.json"; }
feature_default() { jq -r '.vps.default' "$1/package.json"; }
# A dependency key is only a feature dependency (as opposed to some future
# ordinary npm dependency) if, once its npm scope is stripped the same way
# as feature_name(), it names another folder in this repo with its own
# package.json + run.sh.
feature_deps() {
  # Filtering out vps-common/vps-setup in jq itself (rather than piping
  # through `grep -v`) means an empty result - e.g. a feature whose only
  # dependency is vps-common - doesn't leave a `grep` with no matching
  # lines as the last exit status feeding into `set -o pipefail`.
  jq -r '(.dependencies // {}) | keys[] | sub("^@tomgrv/"; "") | select(. != "vps-common" and . != "vps-setup")' "$1/package.json" | while IFS= read -r dep; do
    # if/then, not `[[ ]] && [[ ]] && printf` - under `set -e`, a bad/typo
    # dependency that doesn't resolve to a real folder would make that
    # iteration's compound command fail and abort this loop early,
    # silently dropping every dependency after it instead of just
    # skipping the bad one.
    if [[ -f "$FEATURES_DIR/$dep/package.json" ]] && [[ -f "$FEATURES_DIR/$dep/run.sh" ]]; then
      printf '%s\n' "$dep"
    fi
  done
}
feature_inputs() { pkg_input_names "$1/package.json"; }

feature_dir_for_name() {
  local d
  for d in $(list_feature_dirs); do
    [[ "$(feature_name "$d")" == "$1" ]] && printf '%s\n' "$d" && return 0
  done
  return 1
}

feature_exists() { feature_dir_for_name "$1" >/dev/null 2>&1; }

ALL_NAMES=""
for d in $(list_feature_dirs); do
  ALL_NAMES="$ALL_NAMES $(feature_name "$d")"
done

# set/ask/run - see steps.sh's own header comment.
# shellcheck disable=SC1091
. "$REPO_ROOT/vps-setup/steps.sh"

for name in $ALL_NAMES; do
  d=$(feature_dir_for_name "$name")
  if [[ "$(feature_default "$d")" == "true" ]]; then
    state_set "$name" up
  else
    state_set "$name" skip
  fi
done

FORCE_DOWN=0

usage() {
  echo "Usage: vps-setup [options]"
  echo "       vps-setup                   (no options, on a terminal: interactive menu)"
  echo
  echo "Options:"
  for name in $ALL_NAMES; do
    d=$(feature_dir_for_name "$name")
    printf '  --skip-%-14s Skip %s (%s/)\n' "$name" "$(feature_desc "$d")" "$(basename "$d")"
  done
  echo
  for name in $ALL_NAMES; do
    d=$(feature_dir_for_name "$name")
    [[ "$(feature_default "$d")" == "false" ]] && printf '  --with-%-14s Enable %s (%s/) - opt-in, off by default\n' "$name" "$(feature_desc "$d")" "$(basename "$d")"
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

Off-by-default steps:$(for n in $ALL_NAMES; do d=$(feature_dir_for_name "$n"); [[ "$(feature_default "$d")" == "false" ]] && printf ' %s' "$n"; done)
(pass --with-<step>, or --only-<step>, to run one of these).

Dependencies:$(for n in $ALL_NAMES; do d=$(feature_dir_for_name "$n"); deps=$(feature_deps "$d" | tr '\n' ' '); [[ -n "$deps" ]] && printf ' %s needs %s;' "$n" "$deps"; done)
(enabling a step auto-enables what it needs; --down-<step> is refused while
a dependent step is still enabled).

Every feature lives in its own workspace package: vps-<name>/
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
      [[ "$(feature_default "$d")" == "true" ]] && marker=" * "
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
    if [[ -z "$name" ]]; then
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

if [[ "$#" -eq 0 ]] && [[ -t 0 ]]; then
  run_menu
fi

if [[ -n "$ONLY_LIST" ]]; then
  for name in $ALL_NAMES; do state_set "$name" skip; done
  for name in $ONLY_LIST; do state_set "$name" up; done
fi

pass=0
while [[ "$pass" -lt 3 ]]; do
  changed=0
  for name in $ALL_NAMES; do
    [[ "$(state_get "$name")" == "up" ]] || continue
    d=$(feature_dir_for_name "$name")
    for dep in $(feature_deps "$d"); do
      if [[ "$(state_get "$dep")" == "skip" ]]; then
        zz_log w "[vps-setup] Also enabling '${dep}' (required by '${name}')."
        state_set "$dep" up
        changed=1
      fi
    done
  done
  [[ "$changed" -eq 0 ]] && break
  pass=$((pass + 1))
done

if [[ "$FORCE_DOWN" -ne 1 ]]; then
  for name in $ALL_NAMES; do
    [[ "$(state_get "$name")" == "down" ]] || continue
    for other in $ALL_NAMES; do
      [[ "$other" == "$name" ]] && continue
      [[ "$(state_get "$other")" == "up" ]] || continue
      d=$(feature_dir_for_name "$other")
      for dep in $(feature_deps "$d"); do
        if [[ "$dep" == "$name" ]]; then
          zz_log e "[vps-setup] Refusing to bring '${name}' down: '${other}' depends on it and is still enabled. Also pass --down-${other}, or --force-down to override (may leave '${other}' broken)."
          exit 1
        fi
      done
    done
  done
fi

require_root

# Ask for any input every enabled ("up") step declares that isn't already
# set in the environment - see steps.sh's ask_missing_inputs.
ask_missing_inputs

# ufw (vps-security) only opens this repo's Tailscale-only services
# (see this feature's own package.json) to the tailscale0 interface, so
# running the rest of the install without Tailscale authenticated would
# leave all of them unreachable. Refuse to proceed rather than silently
# produce a VPS nothing can be managed on.
if [[ "$(state_get vps-tailscale)" == "up" ]] && [[ -z "${TAILSCALE_AUTHKEY:-}" ]]; then
  zz_log w "[vps-setup] TAILSCALE_AUTHKEY is not set, but the vps-tailscale step is enabled." \
    "Cockpit, Rancher, the Traefik dashboard, and the k3s API" \
    "are reachable ONLY over Tailscale (see README's Security model) -" \
    "continuing without it would leave all of them unreachable once ufw" \
    "locks the box down. Either:" \
    "  - set TAILSCALE_AUTHKEY (see README's 'Getting the keys you'll need'), or" \
    "  - pass --skip-vps-tailscale to proceed anyway (you can run 'tailscale up'" \
    "    manually later, then: sudo vps-setup --only-vps-tailscale)."
  zz_log e "[vps-setup] Refusing to run with vps-tailscale enabled and TAILSCALE_AUTHKEY unset."
  exit 1
fi

# Tear down requested steps first (in reverse order, so dependents come
# down before what they depend on), then install/reconcile everything
# still enabled.
for name in $(echo "$ALL_NAMES" | tr ' ' '\n' | sed '1!G;h;$!d' | tr '\n' ' '); do
  [[ "$(state_get "$name")" == "down" ]] && run_step "$name" down
done

for name in $ALL_NAMES; do
  case "$(state_get "$name")" in
    up) run_step "$name" up ;;
    *)
      d=$(feature_dir_for_name "$name")
      zz_log w "[vps-setup] Skipping $(feature_desc "$d") ($(basename "$d")/run.sh)"
      ;;
  esac
done

# --- summary: final connection info, printed after every run (also
# callable on its own afterwards - see README's "Running vps-setup"
# section - since none of the values below depend on what this run just
# did versus a previous one).

COCKPIT_HTTP_PORT="${COCKPIT_HTTP_PORT:-$(net_port cockpit_http vps-cockpit)}"
COCKPIT_HTTPS_PORT="${COCKPIT_HTTPS_PORT:-$(net_port cockpit_https vps-cockpit)}"
RANCHER_HTTP_PORT="${RANCHER_HTTP_PORT:-$(net_port rancher_http vps-rancher)}"
RANCHER_HTTPS_PORT="${RANCHER_HTTPS_PORT:-$(net_port rancher_https vps-rancher)}"
TRAEFIK_DASHBOARD_PORT="${TRAEFIK_DASHBOARD_PORT:-$(net_port traefik_dashboard vps-k3s)}"

TAILSCALE_IP="$(tailscale ip -4 2>/dev/null || true)"
HOST_FOR_URLS="${TAILSCALE_IP:-<tailscale-ip>}"
[[ -z "$TAILSCALE_IP" ]] && TAILSCALE_STATUS="not joined yet - run: tailscale up" || TAILSCALE_STATUS="$TAILSCALE_IP"

COCKPIT_USER="$(cat /root/.cockpit-admin-user 2>/dev/null || echo 'not set - run vps-security/run.sh')"
COCKPIT_PASSWORD="$(cat /root/.cockpit-admin-password 2>/dev/null || echo 'not set - run vps-security/run.sh')"

RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-$HOST_FOR_URLS}"
RANCHER_PASSWORD="$(cat /root/.rancher-bootstrap-password 2>/dev/null || echo 'not set - run vps-rancher/run.sh')"

NODE_PUBLIC_IP="$(hostname -I | awk '{print $1}')"

cat <<EOF

======================================================================
 VPS setup complete
======================================================================
 Tailscale IP:        ${TAILSCALE_STATUS}

 Cockpit:             https://${HOST_FOR_URLS}:${COCKPIT_HTTP_PORT}
                       https://${HOST_FOR_URLS}:${COCKPIT_HTTPS_PORT}
                       user:     ${COCKPIT_USER}
                       password: ${COCKPIT_PASSWORD}
                       (saved to /root/.cockpit-admin-user and
                       /root/.cockpit-admin-password; PAM login, same
                       account you'd use on the local console - separate
                       from SSH, which stays key-only)

 Rancher:             https://${RANCHER_HOSTNAME}:${RANCHER_HTTPS_PORT}
                       (also on plain port ${RANCHER_HTTP_PORT})
                       user:     admin
                       password: ${RANCHER_PASSWORD}
                       (saved to /root/.rancher-bootstrap-password; you'll
                       be prompted to change it on first login)

 Docker (Cockpit):    $(command_exists docker && echo "installed - see the Containers tab in Cockpit" || echo "not installed (run vps-dockermanager/run.sh)")
                       If VPS_ADMIN_USER was just added to the docker group,
                       log out/in (or reboot) before it takes effect.

 Traefik (k3s):       public: http://${NODE_PUBLIC_IP} and https://${NODE_PUBLIC_IP}
                       (a "letsencrypt" certResolver is configured and
                       ready to use - it won't issue anything until you
                       add the router.tls.certresolver annotation to your
                       own Ingress; see README)
                       dashboard: http://${HOST_FOR_URLS}:${TRAEFIK_DASHBOARD_PORT}/dashboard/
                       (Tailscale-only, no login - see README's Security model)

 Marketplace:         Apps & Marketplace -> Repositories in Rancher should
                       list "perspikapps-vps" (registered by the
                       vps-marketplace step) - install ArgoCD, Epinio, or
                       any other chart from this repo's catalog from
                       Apps & Marketplace -> Charts. See README's
                       "Rancher Marketplace" section.

 kubectl / helm:      KUBECONFIG=/etc/rancher/k3s/k3s.yaml (already exported
                       via /etc/profile.d/k3s-kubeconfig.sh for new shells)

 Firewall:            ufw is enabled; SSH/HTTP/HTTPS are public (Traefik is
                       this VPS's ingress). Cockpit, Rancher, the Traefik
                       dashboard, and the k3s API are reachable ONLY over
                       the tailscale0 interface - connect via Tailscale
                       first.
======================================================================
EOF
