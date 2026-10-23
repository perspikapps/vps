<!-- @format -->

# vps-security

Firewall / SSH / fail2ban hardening.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `vps-setup`'s install sequence (order and default: `config` in its `package.json`). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

Runs as one step of a full `vps-setup` install/removal, or standalone once `vps-common/run.sh` is reachable (see the root README's [Layout](../README.md#layout)):

```bash
sudo vps-setup --only-vps-security
```

Or directly, from a checkout (`up` is the default action):

```bash
sudo sh vps-security/run.sh up
sudo sh vps-security/run.sh down
```

## Private ports and the FORWARD guard

ufw filters INPUT only. Ports that k3s's ServiceLB (Rancher, the Traefik dashboard) or Docker (the Dokploy UI) publish are DNAT-ed through FORWARD, where both accept them ahead of ufw, so a ufw `private` rule alone leaves them open on the public interface. `up` therefore also installs `vps-private-ports-guard.service` (and `/usr/local/sbin/vps-private-ports-guard`), which drops DNAT-ed connections to every `access: "private"` port of every feature on the default-route interface, first in FORWARD, unless that interface is the private one. `vps-k3s`, `vps-rancher` and `vps-dokploy` run `reapply_private_guard` once they are up, since k3s and Docker insert their own rules when they start. IPv4 only. Verify from outside the private network: `curl -m 5 http://<public-ip>:7083` must time out.

## Removing (`down`)

`down` removes ufw rules (disables ufw entirely), the private-ports guard, sshd hardening, and the fail2ban jail. Leaves the admin user/password `up` created (if any) in place.

```bash
sudo vps-setup --down-vps-security
```

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `SSH_PORT` | no | `22` | SSH port to keep open |
| `VPS_ADMIN_PASSWORD` | no | _(unset)_ | Cockpit/console login password for VPS_ADMIN_USER (or root if unset) |
| `VPS_ADMIN_SSH_KEY` | no | _(unset)_ | Public key to authorize for VPS_ADMIN_USER and root |
| `VPS_ADMIN_USER` | no | _(unset)_ | Optional non-root sudo user to create |
| `VPS_PRIVATE_INTERFACE` | no | _(persisted by the provider, e.g. `vps-tailscale`)_ | Interface that carries `access: "private"` ports (ufw opens them on it only); with none, they stay closed |

## Outputs

| Output | Description |
| --- | --- |
| `COCKPIT_ADMIN_PASSWORD_FILE` | Owner-only env file (`/root/.vps-secrets.env`) holding `COCKPIT_ADMIN_USER` and `COCKPIT_ADMIN_PASSWORD`, the saved Cockpit/console login (older hosts: `/root/.cockpit-admin-*`, migrated on the next run) |

## Dependencies

`vps-common` (shared helpers) only; no other step is required.

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz-use`/`vps-common` wiring, `up()`/`down()`, and `dispatch_action`) plus the `package.json` `bin`/`engines`/`config` shape, and runs the generated guard script against stubbed `ip`/`iptables`. The install itself needs a live root Ubuntu box, so it has no automated coverage - see the root README's [Tests](../README.md#tests).
