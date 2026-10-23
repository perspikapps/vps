#!/bin/sh
# Dokploy (Docker Swarm + Traefik PaaS) through its official installer. Env vars: see README.

set -eu
zz-use "perspikapps/vps/vps-common@${ZZ_SETUP_REF:-main}"
# shellcheck disable=SC1091
. vps-common
# vps-common comes from zz-use's download cache (24h for a branch), while the
# steps come from the fresh checkout: an older cached copy lacks newer helpers.
command -v reapply_private_guard >/dev/null || {
    zz-log e "[vps-setup] The cached vps-common is older than this step. Refresh it and re-run:" \
        "sudo zz-use --force perspikapps/vps/vps-common" && exit 1
}

DOKPLOY_INSTALL_URL=https://dokploy.com/install.sh

# Both halves must exist: a service without Traefik is a broken install, which
# the installer (it re-initialises the swarm) is the right way to repair.
is_dokploy_installed() {
    command_exists docker && docker service inspect dokploy >/dev/null 2>&1 &&
        docker container inspect dokploy-traefik >/dev/null 2>&1
}

up() {
    local ui_port

    ui_port="$(net_port dokploy_ui)"

    if is_dokploy_installed; then
        zz-log i "[vps-setup] Dokploy already installed; not re-running its installer (it resets the swarm)."
    else
        # k3s's ServiceLB holds 80/443 with iptables rules the installer's own
        # port check (ss) cannot see, so it would not notice the clash.
        if command_exists k3s; then
            zz-log e "[vps-setup] k3s is installed and its Traefik owns ports 80/443, which Dokploy's Traefik needs too." \
                "Run one ingress: sudo vps-setup --down-vps-marketplace --down-vps-rancher --down-vps-k3s --with-vps-dokploy" && exit 1
        fi
        # The installer runs 'docker swarm leave --force' first: refuse to take down a swarm that is not Dokploy's.
        if command_exists docker && [ "$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)" = "active" ]; then
            zz-log e "[vps-setup] This host is already in a Docker swarm that is not Dokploy's; the installer would destroy it." \
                "Run 'docker swarm leave --force' yourself if that is what you want, then re-run." && exit 1
        fi
        # The installer calls openssl unconditionally and installs Docker itself when missing.
        if ! command_exists openssl; then
            apt_update_once
            apt_install openssl
        fi
        # Upstream variable names: the installer reads them from its environment.
        export ADVERTISE_ADDR="${ADVERTISE_ADDR:-$(hostname -I | awk '{print $1}')}"
        export DOKPLOY_VERSION="${DOKPLOY_VERSION:-}" DOCKER_SWARM_INIT_ARGS="${DOCKER_SWARM_INIT_ARGS:-}"
        zz-log i "[vps-setup] Running the Dokploy installer (advertise address ${ADVERTISE_ADDR}); it installs Docker if needed..."
        # The official installer needs bash.
        download_run "$DOKPLOY_INSTALL_URL" bash
        is_dokploy_installed || { zz-log e "[vps-setup] The Dokploy installer finished but the dokploy service/Traefik are not there." && exit 1; }
    fi

    # Docker publishes the admin UI past ufw: vps-security's FORWARD guard covers it.
    reapply_private_guard
    ok "Dokploy installed. Admin UI on port ${ui_port}, private access only (the first visit creates the admin account)."
}

down() {
    if command_exists docker; then
        zz-log i "[vps-setup] Removing Dokploy and the applications it deployed (swarm services, volumes, secrets)..."
        docker container rm -f dokploy-traefik 2>/dev/null || true
        docker service rm dokploy dokploy-postgres dokploy-redis 2>/dev/null || true
        docker swarm leave --force 2>/dev/null || true
        # A kept postgres volume would not match the password a reinstall generates.
        docker volume rm -f dokploy dokploy-postgres dokploy-redis 2>/dev/null || true
        docker network rm dokploy-network 2>/dev/null || true
    else
        zz-log w "[vps-setup] Docker not found; nothing to remove besides /etc/dokploy."
    fi
    rm -rf /etc/dokploy
    if [ "${REMOVE_DOCKER:-false}" = "true" ] && command_exists docker; then
        zz-log i "[vps-setup] Removing Docker (REMOVE_DOCKER=true)..."
        systemctl disable --now docker docker.socket containerd 2>/dev/null || true
        apt-mark unhold docker-ce docker-ce-cli docker-ce-rootless-extras 2>/dev/null || true
        apt_purge docker-ce docker-ce-cli docker-ce-rootless-extras docker-buildx-plugin docker-compose-plugin containerd.io docker.io || true
    fi
    ok "Dokploy removed."
}

summary() {
    # Opt-in step: say nothing on a host that never installed it.
    [ -d /etc/dokploy ] || return 0
    cat <<EOF
 Dokploy:             http://$(summary_host):$(net_port dokploy_ui)
                       (private access only; the first visit creates the
                       admin account, so join the private network first.
                       Apps are served by Dokploy's own Traefik on 80/443)
EOF
}

dispatch_action "$@"
