#!/usr/bin/env bash
#
# One-line VPS bootstrapper for a fresh Ubuntu install.
#
#   curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/setup.sh | sudo bash
#
# Clones/updates this repo into /opt/vps-setup and runs the numbered scripts
# in scripts/ in order. Each step is idempotent and can be skipped with an
# env var or CLI flag. Run with --help for options.
#
# Inspired by the modular "leading script + dependent scripts" layout of
# https://github.com/jmilinovich/vps-setup-skill and by the install
# conventions used in devcontainers/features (common-utils): strict bash
# mode, non-interactive apt, idempotent checks, plain colored logging.

set -euo pipefail

REPO_URL="${VPS_SETUP_REPO_URL:-https://github.com/perspikapps/vps.git}"
REPO_REF="${VPS_SETUP_REPO_REF:-main}"
INSTALL_DIR="${VPS_SETUP_DIR:-/opt/vps-setup}"

# Single source of truth for every step: name, script, label, and whether
# it runs by default. Adding a step means editing these three lines and
# nothing else - flag parsing, usage text, and execution below are all
# generated from this table.
STEP_ORDER=(system security tailscale cockpit k3s rancher dockermanager argocd epinio)
declare -A STEP_SCRIPT=(
  [system]=01-system-update.sh
  [security]=02-security-harden.sh
  [tailscale]=03-tailscale.sh
  [cockpit]=04-cockpit.sh
  [k3s]=05-k3s.sh
  [rancher]=06-rancher.sh
  [dockermanager]=07-cockpit-dockermanager.sh
  [argocd]=08-argocd.sh
  [epinio]=09-epinio.sh
)
declare -A STEP_LABEL=(
  [system]="Base system update & essentials"
  [security]="Firewall / SSH / fail2ban hardening"
  [tailscale]="Tailscale install"
  [cockpit]="Cockpit install"
  [k3s]="k3s / kubectl / helm install (includes Traefik configuration)"
  [rancher]="Rancher install"
  [dockermanager]="cockpit-packagekit/files/dockermanager install"
  [argocd]="ArgoCD install"
  [epinio]="Epinio install"
)
# 1 = runs unless --skip-<step>; 0 = only runs with --with-<step> or --only-<step>.
declare -A STEP_DEFAULT=(
  [system]=1 [security]=1 [tailscale]=1 [cockpit]=1 [k3s]=1 [rancher]=1
  [dockermanager]=1 [argocd]=0 [epinio]=0
)

declare -A SKIP=()
for step in "${STEP_ORDER[@]}"; do
  SKIP[$step]=$(( 1 - STEP_DEFAULT[$step] ))
done
declare -a ONLY_STEPS=()

usage() {
  echo "Usage: setup.sh [options]"
  echo
  echo "Options:"
  for step in "${STEP_ORDER[@]}"; do
    printf '  --skip-%-14s Skip %s (%s)\n' "$step" "${STEP_LABEL[$step]}" "${STEP_SCRIPT[$step]}"
  done
  echo
  for step in "${STEP_ORDER[@]}"; do
    [[ "${STEP_DEFAULT[$step]}" -eq 0 ]] && printf '  --with-%-14s Enable %s (%s) - opt-in, off by default\n' "$step" "${STEP_LABEL[$step]}" "${STEP_SCRIPT[$step]}"
  done
  echo
  for step in "${STEP_ORDER[@]}"; do
    printf '  --only-%-14s Run ONLY %s (%s)\n' "$step" "${STEP_SCRIPT[$step]}" "${STEP_LABEL[$step]}"
  done
  cat <<EOF
                        (repeat --only-* to run more than one step; any
                        --only-* flag overrides all --skip-*/--with-* flags)

  -h, --help            Show this help

Off-by-default steps: $(for s in "${STEP_ORDER[@]}"; do [[ "${STEP_DEFAULT[$s]}" -eq 0 ]] && echo -n "$s "; done)
(pass --with-<step>, or --only-<step>, to run one of these).

Note: TAILSCALE_AUTHKEY is required unless --skip-tailscale is passed -
every Tailscale-only service this repo sets up (see network.yaml) is
unreachable without it, so this refuses to run rather than produce a
VPS nothing can be managed on.

Environment variables: see README.md's "Key environment variables"
section for the full list (network.yaml for ports specifically).
EOF
}

for arg in "$@"; do
  case "$arg" in
    --skip-*)
      step="${arg#--skip-}"
      if [[ -n "${STEP_SCRIPT[$step]:-}" ]]; then
        SKIP[$step]=1
      else
        echo "Unknown option: $arg" >&2; usage; exit 1
      fi
      ;;
    --with-*)
      step="${arg#--with-}"
      if [[ -n "${STEP_SCRIPT[$step]:-}" ]]; then
        SKIP[$step]=0
      else
        echo "Unknown option: $arg" >&2; usage; exit 1
      fi
      ;;
    --only-*)
      step="${arg#--only-}"
      if [[ -n "${STEP_SCRIPT[$step]:-}" ]]; then
        ONLY_STEPS+=("$step")
      else
        echo "Unknown option: $arg" >&2; usage; exit 1
      fi
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage; exit 1 ;;
  esac
done

# Any --only-<step> flag overrides --skip-*/--with-*: start from "skip
# everything" and re-enable just the requested step(s).
if [[ "${#ONLY_STEPS[@]}" -gt 0 ]]; then
  for step in "${STEP_ORDER[@]}"; do
    SKIP[$step]=1
  done
  for step in "${ONLY_STEPS[@]}"; do
    SKIP[$step]=0
  done
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "[vps-setup] This script must be run as root (use sudo)." >&2
  exit 1
fi

# ufw (scripts/02) only opens this repo's Tailscale-only services (see
# network.yaml) to the tailscale0 interface, so running the rest of the
# install without Tailscale authenticated would leave all of them
# unreachable. Refuse to proceed rather than silently produce a VPS
# nothing can be managed on.
if [[ "${SKIP[tailscale]}" -eq 0 && -z "${TAILSCALE_AUTHKEY:-}" ]]; then
  echo "[vps-setup] TAILSCALE_AUTHKEY is not set, but the tailscale step is enabled." >&2
  echo "[vps-setup] Cockpit, Rancher, ArgoCD, the Traefik dashboard, and the k3s API" >&2
  echo "[vps-setup] are reachable ONLY over Tailscale (see README's Security model) -" >&2
  echo "[vps-setup] continuing without it would leave all of them unreachable once ufw" >&2
  echo "[vps-setup] locks the box down. Either:" >&2
  echo "[vps-setup]   - set TAILSCALE_AUTHKEY (see README's 'Getting the keys you'll need'), or" >&2
  echo "[vps-setup]   - pass --skip-tailscale to proceed anyway (you can run 'tailscale up'" >&2
  echo "[vps-setup]     manually later, then: sudo bash setup.sh --only-tailscale)." >&2
  exit 1
fi

echo "[vps-setup] repo=${REPO_URL} ref=${REPO_REF} dir=${INSTALL_DIR}"
if [[ -z "${VPS_SETUP_REPO_REF:-}" && "$REPO_REF" == "main" ]]; then
  echo "[vps-setup] (VPS_SETUP_REPO_REF not set - using 'main'. Note: a plain" >&2
  echo "[vps-setup]  shell 'export' before '| sudo bash' is dropped by sudo;" >&2
  echo "[vps-setup]  set it on the sudo line instead, e.g. 'sudo VPS_SETUP_REPO_REF=... bash'.)" >&2
fi

if [[ -d "$INSTALL_DIR/.git" ]]; then
  echo "[vps-setup] Updating existing checkout in $INSTALL_DIR..."
  # A one-off `fetch origin <ref>` populates FETCH_HEAD but does NOT create
  # or update a remote-tracking ref like origin/<ref> (that only happens
  # with the repo's configured fetch refspec) - so reset against FETCH_HEAD
  # directly, which works for branches, tags, and commit SHAs alike.
  git -C "$INSTALL_DIR" fetch --depth 1 origin "$REPO_REF"
  git -C "$INSTALL_DIR" checkout -q -B "$REPO_REF" FETCH_HEAD
  git -C "$INSTALL_DIR" reset --hard FETCH_HEAD
elif [[ -d "$INSTALL_DIR" ]]; then
  echo "[vps-setup] $INSTALL_DIR exists and is not a git checkout; running scripts in place."
else
  echo "[vps-setup] Cloning $REPO_URL (ref: $REPO_REF) into $INSTALL_DIR..."
  command -v git >/dev/null 2>&1 || (apt-get update -y && apt-get install -y --no-install-recommends git)
  git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# shellcheck disable=SC1091
source "$INSTALL_DIR/lib/common.sh"

require_root
require_ubuntu

run_step() {
  local step="$1" skip="${SKIP[$1]}" script="${STEP_SCRIPT[$1]}" label="${STEP_LABEL[$1]}"
  if [[ "$skip" -eq 1 ]]; then
    warn "Skipping ${label} (${script})"
    return
  fi
  log "=== Running ${label} (${script}) ==="
  local rc=0
  bash "$INSTALL_DIR/scripts/${script}" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    die "Step '${label}' (${script}) failed (exit ${rc}) - see the error above." \
        "Fix it and re-run just this step with: sudo bash setup.sh --only-${step}"
  fi
  ok "=== Done: ${label} ==="
}

for step in "${STEP_ORDER[@]}"; do
  run_step "$step"
done
bash "$INSTALL_DIR/scripts/99-summary.sh"
