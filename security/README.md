<!-- @format -->

# security

Firewall / SSH / fail2ban hardening.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `dispatch.sh`'s install sequence (order `1`, enabled by default). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

Runs as one step of a full `dispatch.sh` install/removal, or standalone once `common/run.sh` is reachable (see the root README's [Layout](../README.md#layout)):

```bash
sudo sh dispatch.sh --only-security
```

Or directly, from a checkout (`up` is the default action):

```bash
sudo bash security/run.sh up
sudo bash security/run.sh down
```

## Removing (`down`)

`down` removes ufw rules (disables ufw entirely), sshd hardening, and the fail2ban jail. Leaves the admin user/password `up` created (if any) in place.

```bash
sudo sh dispatch.sh --down-security
```

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `SSH_PORT` | no | `22` | SSH port to keep open |
| `VPS_ADMIN_PASSWORD` | no | _(unset)_ | Cockpit/console login password for VPS_ADMIN_USER (or root if unset) |
| `VPS_ADMIN_SSH_KEY` | no | _(unset)_ | Public key to authorize for VPS_ADMIN_USER and root |
| `VPS_ADMIN_USER` | no | _(unset)_ | Optional non-root sudo user to create |

## Outputs

| Output | Description |
| --- | --- |
| `COCKPIT_ADMIN_PASSWORD_FILE` | Path to the saved Cockpit/console login password (/root/.cockpit-admin-password) |

## Dependencies

`common` (shared helpers). `dispatch.sh` auto-enables these when this step is enabled - see the root README's [Dependencies between steps](../README.md#dependencies-between-steps).

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz_use`/`common` wiring, `up()`/`down()`, and `dispatch_action`) plus `package.json`'s `bin`/`vps` fields. The step itself (a live apt/Helm/k3s install) needs a real root Ubuntu box to actually run - see the root README's [Tests](../README.md#tests) section for the full picture.
