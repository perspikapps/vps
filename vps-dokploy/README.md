<!-- @format -->

# vps-dokploy

[Dokploy](https://dokploy.com) (Docker Swarm + Traefik PaaS) through its official installer.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `vps-setup`'s install sequence (order and default: `config` in its `package.json`). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

**Opt-in** (`config.default: false`), and an **alternative to `vps-k3s`**, not an addition: both run a Traefik that must own ports 80/443. `config.conflicts` makes `zz-setup` abort before any step starts when both are selected, and `up` itself refuses to run while k3s is installed (a host set up by an earlier run).

## Usage

Runs as one step of a full `vps-setup` install/removal, or standalone once `vps-common/run.sh` is reachable (see the root README's [Layout](../README.md#layout)):

```bash
# Fresh box, Dokploy instead of the k3s/Rancher stack:
sudo vps-setup --skip-vps-k3s --skip-vps-rancher --skip-vps-marketplace --with-vps-dokploy

# Only the Dokploy step:
sudo vps-setup --only-vps-dokploy
```

Or directly, from a checkout (`up` is the default action):

```bash
sudo bash vps-dokploy/run.sh up
sudo bash vps-dokploy/run.sh down
```

`up` installs Docker (the installer pins and holds `docker-ce`) if it is missing, initialises the swarm, starts Dokploy, its Postgres and its Traefik, then installs the admin-port guard below. A re-run is safe: once Dokploy is there the upstream installer is **not** run again, because it starts with `docker swarm leave --force`. To upgrade, use Dokploy's own update (UI: Settings, Server) rather than this step.

## Access and security

- **Admin UI** on port `3000`, declared `private`: `vps-security` opens it on the private interface only, and the final summary prints `http://<private-ip>:3000`. The first visit creates the admin account, so join the private network before opening it.
- **Docker bypasses ufw.** Published container ports are NAT-ed ahead of ufw's rules, so a ufw rule alone would leave `3000` open to the internet. `up` therefore installs `vps-dokploy-guard.service`, which drops port `3000` arriving on the default-route interface in Docker's `DOCKER-USER` chain (re-applied after every Docker start). Check it from outside the private network: `curl -m 5 http://<public-ip>:3000` must time out. IPv4 only.
- **Apps** deployed through Dokploy are served by its own Traefik on `80`/`443` (public). Any other port an app publishes is NAT-ed past ufw too: publish only what you mean to expose, or front it with Dokploy's domains.
- `/etc/dokploy` is created `777` by the upstream installer and left as is.

## Removing (`down`)

`down` removes Dokploy **and everything it deployed**: the Traefik container, the swarm services, the `dokploy*` volumes, the swarm itself and `/etc/dokploy`. Docker stays unless `REMOVE_DOCKER=true`. The old `vps-dockermanager` Cockpit plugin is gone; `cockpit-packagekit` and `cockpit-files` now come with `vps-cockpit`.

```bash
sudo vps-setup --down-vps-dokploy
```

## Environment variables

Passed to the upstream installer under its own names.

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `ADVERTISE_ADDR` | no | first IPv4 of the host | Address Docker Swarm advertises |
| `DOCKER_SWARM_INIT_ARGS` | no | _(empty)_ | Extra `docker swarm init` flags, e.g. `--default-addr-pool 172.20.0.0/16` to avoid clashing with a VPC |
| `DOKPLOY_VERSION` | no | latest stable | Dokploy release tag to install (e.g. `v0.26.6`, `canary`) |
| `REMOVE_DOCKER` | no | `false` | Also remove Docker itself on down (true/false) |

The ports (`80`/`443` public, `3000` private) are fixed by the installer; overriding `DOKPLOY_*_PORT` only changes the firewall, not Dokploy.

## Dependencies

Only `vps-common` (shared helpers). It needs no other step, and conflicts with `vps-k3s` (see above).

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz-use`/`vps-common` wiring, `up()`/`down()`, and `dispatch_action`), the k3s and foreign-swarm guards, the `package.json` `bin`/`engines`/`config` shape and its declared ports. The install itself needs a live root Ubuntu box with Docker, so it has no automated coverage - see the root README's [Tests](../README.md#tests).
