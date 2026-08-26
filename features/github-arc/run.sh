#!/usr/bin/env bash
# Install GitHub Actions Runner Controller (ARC) onto the k3s cluster from
# features/k3s, following the official quickstart:
# https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/get-started
#
# Both the controller (gha-runner-scale-set-controller) and a runner scale
# set (gha-runner-scale-set) are installed into a single "github" namespace,
# via GitHub App authentication (the auth method the docs recommend over a
# PAT). The GitHub App itself has to already exist and be installed on the
# target org/repo - this script only wires its credentials into the cluster.
#
# Env vars:
#   GITHUB_ARC_CONFIG_URL       - org or repo URL runners register against,
#                                 e.g. https://github.com/perspikapps or
#                                 https://github.com/perspikapps/vps
#                                 (required)
#   GITHUB_ARC_APP_ID           - GitHub App ID (required)
#   GITHUB_ARC_APP_INSTALLATION_ID - GitHub App installation ID (required)
#   GITHUB_ARC_APP_PRIVATE_KEY_FILE - path to the GitHub App's private key
#                                 PEM file (required)
#   GITHUB_ARC_RUNNER_SCALE_SET_NAME - name of the runner scale set
#                                 (default: arc-runner-set)
#   GITHUB_ARC_MIN_RUNNERS       - minimum idle runners (default: 0)
#   GITHUB_ARC_MAX_RUNNERS       - maximum runners (default: 5)
#   GITHUB_ARC_CONTROLLER_CHART_VERSION - pin the controller chart version
#                                 (optional, default: latest)
#   GITHUB_ARC_RUNNER_SET_CHART_VERSION - pin the runner scale set chart
#                                 version (optional, default: latest)
#   GITHUB_ARC_INSTALL_TIMEOUT   - how long to wait for each helm install
#                                 (default: 10m)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../lib/common.sh"

NAMESPACE=github
CONTROLLER_RELEASE=arc
RUNNER_SET_RELEASE=arc-runner-set
SECRET_NAME=github-app-secret

up() {
require_root
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
command_exists kubectl || die "kubectl not found; run features/k3s/run.sh first."
command_exists helm || die "helm not found; run features/k3s/run.sh first."

[[ -n "${GITHUB_ARC_CONFIG_URL:-}" ]] || die "GITHUB_ARC_CONFIG_URL is required (the org or repo URL runners should register against)."
[[ -n "${GITHUB_ARC_APP_ID:-}" ]] || die "GITHUB_ARC_APP_ID is required."
[[ -n "${GITHUB_ARC_APP_INSTALLATION_ID:-}" ]] || die "GITHUB_ARC_APP_INSTALLATION_ID is required."
[[ -n "${GITHUB_ARC_APP_PRIVATE_KEY_FILE:-}" ]] || die "GITHUB_ARC_APP_PRIVATE_KEY_FILE is required (path to the GitHub App's private key PEM)."
[[ -r "${GITHUB_ARC_APP_PRIVATE_KEY_FILE}" ]] || die "GITHUB_ARC_APP_PRIVATE_KEY_FILE (${GITHUB_ARC_APP_PRIVATE_KEY_FILE}) is not readable."

GITHUB_ARC_RUNNER_SCALE_SET_NAME="${GITHUB_ARC_RUNNER_SCALE_SET_NAME:-arc-runner-set}"
GITHUB_ARC_MIN_RUNNERS="${GITHUB_ARC_MIN_RUNNERS:-0}"
GITHUB_ARC_MAX_RUNNERS="${GITHUB_ARC_MAX_RUNNERS:-5}"
GITHUB_ARC_INSTALL_TIMEOUT="${GITHUB_ARC_INSTALL_TIMEOUT:-10m}"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

log "Creating/updating the GitHub App secret (${SECRET_NAME}) in namespace ${NAMESPACE}..."
kubectl create secret generic "$SECRET_NAME" \
  --namespace="$NAMESPACE" \
  --from-literal=github_app_id="$GITHUB_ARC_APP_ID" \
  --from-literal=github_app_installation_id="$GITHUB_ARC_APP_INSTALLATION_ID" \
  --from-file=github_app_private_key="$GITHUB_ARC_APP_PRIVATE_KEY_FILE" \
  --dry-run=client -o yaml | kubectl apply -f -

CONTROLLER_VERSION_ARG=()
[[ -n "${GITHUB_ARC_CONTROLLER_CHART_VERSION:-}" ]] && CONTROLLER_VERSION_ARG=(--version "$GITHUB_ARC_CONTROLLER_CHART_VERSION")

log "Installing/upgrading the ARC controller (timeout ${GITHUB_ARC_INSTALL_TIMEOUT})..."
helm upgrade --install "$CONTROLLER_RELEASE" \
  --namespace "$NAMESPACE" \
  "${CONTROLLER_VERSION_ARG[@]}" \
  --wait --timeout "$GITHUB_ARC_INSTALL_TIMEOUT" \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller

RUNNER_SET_VERSION_ARG=()
[[ -n "${GITHUB_ARC_RUNNER_SET_CHART_VERSION:-}" ]] && RUNNER_SET_VERSION_ARG=(--version "$GITHUB_ARC_RUNNER_SET_CHART_VERSION")

log "Installing/upgrading the runner scale set '${GITHUB_ARC_RUNNER_SCALE_SET_NAME}' (timeout ${GITHUB_ARC_INSTALL_TIMEOUT})..."
helm upgrade --install "$RUNNER_SET_RELEASE" \
  --namespace "$NAMESPACE" \
  --set githubConfigUrl="$GITHUB_ARC_CONFIG_URL" \
  --set githubConfigSecret="$SECRET_NAME" \
  --set minRunners="$GITHUB_ARC_MIN_RUNNERS" \
  --set maxRunners="$GITHUB_ARC_MAX_RUNNERS" \
  --set runnerScaleSetName="$GITHUB_ARC_RUNNER_SCALE_SET_NAME" \
  "${RUNNER_SET_VERSION_ARG[@]}" \
  --wait --timeout "$GITHUB_ARC_INSTALL_TIMEOUT" \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set

ok "GitHub Actions Runner Controller installed in namespace ${NAMESPACE}."
ok "Runner scale set '${GITHUB_ARC_RUNNER_SCALE_SET_NAME}' registered against ${GITHUB_ARC_CONFIG_URL}."
}

# Uninstalls both Helm releases, the secret, and the namespace.
down() {
  require_root
  export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
  command_exists kubectl || { warn "kubectl not found; nothing to remove."; return; }
  command_exists helm || { warn "helm not found; nothing to remove."; return; }
  if helm status "$RUNNER_SET_RELEASE" -n "$NAMESPACE" >/dev/null 2>&1; then
    log "Uninstalling Helm release ${RUNNER_SET_RELEASE} (namespace ${NAMESPACE})..."
    helm uninstall "$RUNNER_SET_RELEASE" -n "$NAMESPACE" --wait || warn "helm uninstall ${RUNNER_SET_RELEASE} timed out or failed."
  fi
  helm_teardown "$NAMESPACE" "$CONTROLLER_RELEASE"
  ok "GitHub Actions Runner Controller removed."
}

dispatch_action "$@"
