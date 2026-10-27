<!-- @format -->

# svc-cockpit

Cockpit install, with the `cockpit-packagekit` (software updates) and `cockpit-files` modules.

Part of [`vps`](https://github.com/tomgrv/vps) · order 3 · on by default · needs root, Ubuntu · [how steps work](../README.md#contributing).

## Usage

```bash
sudo vps-setup --only-svc-cockpit      # just this step (it is on by default)
sudo vps-setup --skip-svc-cockpit      # leave it out of a full run
sudo vps-setup --down-svc-cockpit      # remove it
sudo zz-setup ./ -o svc-cockpit         # without vps-setup, from a checkout
```

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `ZZ_SECRETS_FILE` | no | `/root/.vps-secrets.env` | Owner-only env file holding the credentials the steps generate |
| `COCKPIT_HTTPS_PORT` | no | `9083` | Cockpit HTTPS port |
| `COCKPIT_HTTP_PORT` | no | `9080` | Cockpit HTTP port |

## Ports and access

| Port   | Access  | Override             | What |
| ------ | ------- | -------------------- | ---- |
| `9080` | private | `COCKPIT_HTTP_PORT`  |      |
| `9083` | private | `COCKPIT_HTTPS_PORT` |      |

`public` ports are open to everyone; `private` ones only on the internal interface (`vps-security`).

## Removing (`down`)

`down` removes the Cockpit packages (including `cockpit-packagekit` and `cockpit-files`) and socket config.

```bash
sudo vps-setup --down-svc-cockpit
```

## Dependencies

No other step is required.

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz-use` line, the `up`/`down` dispatch, and that nothing but `zz-colors` is sourced) plus the `package.json` `bin`/`engines`/`config` shape. The install itself needs a live root Ubuntu box, so it has no automated coverage - see the root README's [Tests](../README.md#contributing).
