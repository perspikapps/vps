<!-- @format -->

# vps-security

Firewall / SSH / fail2ban hardening.

Part of [`vps`](https://github.com/tomgrv/vps) · order 2 · on by default · needs root, Ubuntu · [how steps work](../README.md#contributing).

## Usage

```bash
sudo vps-setup --only-vps-security      # just this step (it is on by default)
sudo vps-setup --skip-vps-security      # leave it out of a full run
sudo vps-setup --down-vps-security      # remove it
sudo zz-setup ./ -o vps-security         # without vps-setup, from a checkout
```

## Private ports and the FORWARD guard

ufw filters INPUT only. Ports that k3s's ServiceLB (the Traefik dashboard) or Docker (the Dokploy UI) publish are DNAT-ed through FORWARD, where both accept them ahead of ufw, so a ufw `private` rule alone leaves them open on the public interface. `up` therefore also installs `vps-private-ports-guard.service` (and `/usr/local/sbin/vps-private-ports-guard`), which drops DNAT-ed connections to every `access: "private"` port of every feature on the default-route interface, first in FORWARD, unless that interface is the private one. `svc-k3s`, `app-coder` and `vps-dokploy` run `reapply_private_guard` once they are up, since k3s and Docker insert their own rules when they start. IPv4 only. Verify from outside the internal network: `curl -m 5 http://<public-ip>:9083` must time out.

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `ZZ_SECRETS_FILE` | no | `/root/.vps-secrets.env` | Owner-only env file holding the credentials the steps generate |
| `SYSTEM_SSH_PORT` | no | `22` | SSH port to keep open |
| `SYSTEM_ADMIN_PASSWORD` | no | _(unset)_ | Cockpit/console login password for SYSTEM_ADMIN_USER (or root if unset) |
| `SYSTEM_ADMIN_SSH_KEY` | no | _(unset)_ | Public key to authorize for SYSTEM_ADMIN_USER and root |
| `SYSTEM_ADMIN_USER` | no | _(unset)_ | Optional non-root sudo user to create |
| `SYSTEM_INTERNAL_INTERFACE` | no | _(persisted by the provider, e.g. `svc-tailscale`)_ | Interface that carries `access: "private"` ports (ufw opens them on it only); with none, they stay closed |

## Ports and access

| Port | Access | Override          | What |
| ---- | ------ | ----------------- | ---- |
| `22` | public | `SYSTEM_SSH_PORT` | SSH  |

`public` ports are open to everyone; `private` ones only on the internal interface (`vps-security`).

## Outputs

| Output | Description |
| --- | --- |
| `COCKPIT_ADMIN_PASSWORD_FILE` | Owner-only env file (`/root/.vps-secrets.env`) holding `COCKPIT_ADMIN_USER` and `COCKPIT_ADMIN_PASSWORD`, the saved Cockpit/console login (older hosts: `/root/.cockpit-admin-*`, migrated on the next run) |

## Removing (`down`)

On dnf and zypper systems (Amazon Linux, SUSE) `up` uses firewalld instead of ufw: public ports go to the `public` zone, private ports to the `internal` zone bound to the internal interface, and the zones' default services are removed. The sshd unit is `sshd` there (`ssh` on Debian), and the admin user is created with `useradd`. fail2ban must be available in the distribution's repositories.

`down` removes ufw rules (disables ufw entirely), the private-ports guard, sshd hardening, and the fail2ban jail. Leaves the admin user/password `up` created (if any) in place.

```bash
sudo vps-setup --down-vps-security
```

## Dependencies

No other step is required.

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz-use` line, the `up`/`down` dispatch, and that nothing but `zz-colors` is sourced) plus the `package.json` `bin`/`engines`/`config` shape, and runs the generated guard script against stubbed `ip`/`iptables`. The install itself needs a live root Ubuntu box, so it has no automated coverage - see the root README's [Tests](../README.md#contributing).
