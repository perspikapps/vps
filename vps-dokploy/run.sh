#!/bin/sh
# Dokploy (Docker Swarm + Traefik PaaS) through its official installer. Env vars: see README.

set -eu
export DEBIAN_FRONTEND=noninteractive
zz-use zz-colors zz-log zz-install
# shellcheck disable=SC1091
. zz-colors

DOKPLOY_INSTALL_URL=https://dokploy.com/install.sh

# Both halves must exist: a service without Traefik is a broken install, which
# the installer (it re-initialises the swarm) is the right way to repair.
is_dokploy_installed() {
    command -v docker >/dev/null 2>&1 && docker service inspect dokploy >/dev/null 2>&1 &&
        docker container inspect dokploy-traefik >/dev/null 2>&1
}

up() {
    local ui_port

    ui_port="$(vps-network port system_dokploy_ui)"

    if is_dokploy_installed; then
        zz-log i "[vps-setup] Dokploy already installed; not re-running its installer (it resets the swarm)."
    else
        # k3s's ServiceLB holds 80/443 with iptables rules the installer's own
        # port check (ss) cannot see, so it would not notice the clash.
        if command -v k3s >/dev/null 2>&1; then
            zz-log e "[vps-setup] k3s is installed and its Traefik owns ports 80/443, which Dokploy's Traefik needs too." \
                "Run one ingress: sudo vps-setup --down-app-rancher --down-vps-k3s --with-vps-dokploy" && exit 1
        fi
        # The installer runs 'docker swarm leave --force' first: refuse to take down a swarm that is not Dokploy's.
        if command -v docker >/dev/null 2>&1 && [ "$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)" = "active" ]; then
            zz-log e "[vps-setup] This host is already in a Docker swarm that is not Dokploy's; the installer would destroy it." \
                "Run 'docker swarm leave --force' yourself if that is what you want, then re-run." && exit 1
        fi
        # The installer calls openssl unconditionally and installs Docker itself when missing.
        command -v openssl >/dev/null 2>&1 || zz-install openssl
        # Upstream variable names: the installer reads them from its environment.
        # the installer reads its own variable names (ADVERTISE_ADDR, DOKPLOY_VERSION, DOCKER_SWARM_INIT_ARGS)
        export ADVERTISE_ADDR="${SYSTEM_DOKPLOY_ADVERTISE_ADDR:-$(hostname -I | awk '{print $1}')}"
        export DOKPLOY_VERSION="${SYSTEM_DOKPLOY_VERSION:-}" DOCKER_SWARM_INIT_ARGS="${SYSTEM_DOKPLOY_DOCKER_SWARM_INIT_ARGS:-}"
        zz-log i "[vps-setup] Running the Dokploy installer (advertise address ${ADVERTISE_ADDR}); it installs Docker if needed..."
        # The official installer needs bash.
        zz-install -u "$DOKPLOY_INSTALL_URL" -x bash dokploy
        is_dokploy_installed || { zz-log e "[vps-setup] The Dokploy installer finished but the dokploy service/Traefik are not there." && exit 1; }
    fi

    # Docker publishes the admin UI past ufw: vps-security's FORWARD guard covers it.
    vps-network reapply-guard
    zz-log s "[vps-setup] Dokploy installed. Admin UI on port ${ui_port}, private access only (the first visit creates the admin account)."
}

down() {
    if command -v docker >/dev/null 2>&1; then
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
    if [ "${SYSTEM_DOKPLOY_REMOVE_DOCKER:-false}" = "true" ] && command -v docker >/dev/null 2>&1; then
        zz-log i "[vps-setup] Removing Docker (SYSTEM_DOKPLOY_REMOVE_DOCKER=true)..."
        systemctl disable --now docker docker.socket containerd 2>/dev/null || true
        apt-mark unhold docker-ce docker-ce-cli docker-ce-rootless-extras 2>/dev/null || true
        zz-install -r docker-ce docker-ce-cli docker-ce-rootless-extras docker-buildx-plugin docker-compose-plugin containerd.io docker.io || true
    fi
    zz-log s "[vps-setup] Dokploy removed."
}

summary() {
    # Opt-in step: say nothing on a host that never installed it.
    [ -d /etc/dokploy ] || return 0
    vps-network summary-block Dokploy \
        "apps served by Dokploy's own Traefik on 80/443" - \
        "http://localhost:$(vps-network port system_dokploy_ui) (admin UI, on the VPS; also http://$(vps-network summary-host):$(vps-network port system_dokploy_ui) on the internal address)" \
        "The first visit creates the admin account: join the internal network first."
}

case "${1:-}" in
    up | down) "$1" ;;
    summary) if command -v summary >/dev/null 2>&1; then summary; fi ;;
    *) zz-log e "Usage: $0 up|down|summary" && exit 1 ;;
esac
