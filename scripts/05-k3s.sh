#!/usr/bin/env bash
# Install a single-node k3s cluster, expose kubectl, and install Helm.
#
# Env vars:
#   K3S_VERSION   - pin a k3s version (optional, default: latest stable)
#   K3S_EXTRA_ARGS - extra flags passed to the k3s installer (optional)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

require_root

if command_exists k3s; then
  log "k3s already installed ($(k3s --version | head -n1))."
else
  log "Installing k3s..."
  # Traefik is disabled: Rancher (scripts/06) manages its own ingress/service.
  INSTALL_K3S_EXEC="server --disable traefik ${K3S_EXTRA_ARGS:-}"
  export INSTALL_K3S_EXEC
  [[ -n "${K3S_VERSION:-}" ]] && export INSTALL_K3S_VERSION="$K3S_VERSION"
  retry curl -fsSL https://get.k3s.io -o /tmp/k3s-install.sh
  sh /tmp/k3s-install.sh
  rm -f /tmp/k3s-install.sh
fi

systemctl enable --now k3s

log "Waiting for k3s node to become Ready..."
for i in $(seq 1 30); do
  if k3s kubectl get nodes 2>/dev/null | grep -q ' Ready'; then
    break
  fi
  sleep 5
done
k3s kubectl get nodes

# k3s already ships a kubectl symlink; make sure it's on PATH as /usr/local/bin/kubectl.
if [[ ! -e /usr/local/bin/kubectl ]]; then
  ln -s "$(command -v k3s)" /usr/local/bin/kubectl
fi

# Make the kubeconfig usable by kubectl/helm without --kubeconfig flags.
mkdir -p /etc/rancher/k3s
KUBECONFIG_PATH=/etc/rancher/k3s/k3s.yaml
chmod 644 "$KUBECONFIG_PATH"
ensure_line "export KUBECONFIG=${KUBECONFIG_PATH}" /etc/profile.d/k3s-kubeconfig.sh
chmod 644 /etc/profile.d/k3s-kubeconfig.sh
export KUBECONFIG="$KUBECONFIG_PATH"

if command_exists helm; then
  log "Helm already installed ($(helm version --short))."
else
  log "Installing Helm..."
  retry curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o /tmp/get-helm-3.sh
  chmod +x /tmp/get-helm-3.sh
  /tmp/get-helm-3.sh
  rm -f /tmp/get-helm-3.sh
fi

ok "k3s, kubectl and helm are installed. KUBECONFIG=${KUBECONFIG_PATH}"
