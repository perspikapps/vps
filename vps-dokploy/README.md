<!-- @format -->

# vps-dokploy

[Dokploy](https://dokploy.com) (Docker Swarm + Traefik PaaS) through its official installer.

**Opt-in** (`config.default: false`), and an **alternative to `svc-k3s`**, not an addition: both run a Traefik that must own ports 80/443. `config.conflicts` makes `zz-setup` abort before any step starts when both are selected, and `up` itself refuses to run while k3s is installed (a host set up by an earlier run).

Part of [`vps`](https://github.com/tomgrv/vps) · order 6 · opt-in · needs root, Ubuntu · cannot run with `svc-k3s` · [how steps work](../README.md#contributing).

## Usage

```bash
sudo vps-setup --with-vps-dokploy      # add it to a full run
sudo vps-setup --only-vps-dokploy      # just this step
sudo vps-setup --down-vps-dokploy      # remove it
sudo zz-setup ./ -o vps-dokploy         # without vps-setup, from a checkout
```

`up` installs Docker (the installer pins and holds `docker-ce`) if it is missing, initialises the swarm, starts Dokploy, its Postgres and its Traefik, then re-applies `vps-security`'s private-ports guard (see below). A re-run is safe: once Dokploy is there the upstream installer is **not** run again, because it starts with `docker swarm leave --force`. To upgrade, use Dokploy's own update (UI: Settings, Server) rather than this step.

## Access and security

- **Admin UI** on port `3000`, declared `private`: `vps-security` opens it on the internal interface only, and the final summary prints `http://<internal-ip>:3000`. The first visit creates the admin account, so join the internal network before opening it.
- **Docker bypasses ufw.** Published container ports are NAT-ed ahead of ufw's rules, so a ufw rule alone would leave `3000` open to the internet. `vps-security`'s `vps-private-ports-guard.service` drops DNAT-ed connections to every `private` port (this one included) on the default-route interface, and `up` re-applies it once Docker is running. Check it from outside the internal network: `curl -m 5 http://<public-ip>:3000` must time out. It therefore needs `vps-security` (on by default); without it nothing here is private. IPv4 only.
- **Apps** deployed through Dokploy are served by its own Traefik on `80`/`443` (public). Any other port an app publishes is NAT-ed past ufw too: publish only what you mean to expose, or front it with Dokploy's domains.
- `/etc/dokploy` is created `777` by the upstream installer and left as is.

## Environment variables

Passed to the upstream installer under its own names.

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `SYSTEM_DOKPLOY_ADVERTISE_ADDR` | no | first IPv4 of the host | Address Docker Swarm advertises |
| `SYSTEM_DOKPLOY_DOCKER_SWARM_INIT_ARGS` | no | _(empty)_ | Extra `docker swarm init` flags, e.g. `--default-addr-pool 172.20.0.0/16` to avoid clashing with a VPC |
| `SYSTEM_DOKPLOY_VERSION` | no | latest stable | Dokploy release tag to install (e.g. `v0.26.6`, `canary`) |

The ports (`80`/`443` public, `3000` private) are fixed by the installer; overriding `DOKPLOY_*_PORT` only changes the firewall, not Dokploy.

## Ports and access

| Port   | Access  | Override                    | What                                                                                                |
| ------ | ------- | --------------------------- | --------------------------------------------------------------------------------------------------- |
| `80`   | public  | `SYSTEM_DOKPLOY_HTTP_PORT`  | Dokploy Traefik HTTP, also required for the Lets Encrypt HTTP-01 challenge (fixed by the installer) |
| `443`  | public  | `SYSTEM_DOKPLOY_HTTPS_PORT` | Dokploy Traefik HTTPS (fixed by the installer)                                                      |
| `3000` | private | `SYSTEM_DOKPLOY_UI_PORT`    | Dokploy admin UI (fixed by the installer)                                                           |

`public` ports are open to everyone; `private` ones only on the internal interface (`vps-security`).

## Removing (`down`)

`down` removes Dokploy **and everything it deployed**: the Traefik container, the swarm services, the `dokploy*` volumes, the swarm itself and `/etc/dokploy`. Docker itself is removed too (its installer put it there). The old `vps-dockermanager` Cockpit plugin is gone; `cockpit-packagekit` and `cockpit-files` now come with `svc-cockpit`.

```bash
sudo vps-setup --down-vps-dokploy
```

## Dependencies

It needs no other step, and conflicts with `svc-k3s` (see above).

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz-use` line, the `up`/`down` dispatch, and that nothing but `zz-colors` is sourced), the k3s and foreign-swarm guards, the `package.json` `bin`/`engines`/`config` shape and its declared ports. The install itself needs a live root Ubuntu box with Docker, so it has no automated coverage - see the root README's [Tests](../README.md#contributing).
