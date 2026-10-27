<!-- @format -->

# vps-cockpit

Cockpit install, with the `cockpit-packagekit` (software updates) and `cockpit-files` modules.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `vps-setup`'s install sequence (order and default: `config` in its `package.json`). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

Runs as one step of a full `vps-setup` install/removal, or on its own through `zz-setup`, from a checkout:

```bash
sudo vps-setup --only-vps-cockpit
```

Or from a checkout, without `vps-setup` (`up` by default; `zz-setup` runs the step's `run.sh`):

```bash
sudo zz-setup ./ -o vps-cockpit
sudo zz-setup ./ -d vps-cockpit
```

## Removing (`down`)

`down` removes the Cockpit packages (including `cockpit-packagekit` and `cockpit-files`) and socket config.

```bash
sudo vps-setup --down-vps-cockpit
```

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `SYSTEM_SECRETS_FILE` | no | `/root/.vps-secrets.env` | Owner-only env file holding the credentials the steps generate |
| `SYSTEM_COCKPIT_HTTPS_PORT` | no | `9083` | Cockpit HTTPS port |
| `SYSTEM_COCKPIT_HTTP_PORT` | no | `9080` | Cockpit HTTP port |

## Dependencies

No other step is required.

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz-use` line, the `up`/`down` dispatch, and that nothing but `zz-colors` is sourced) plus the `package.json` `bin`/`engines`/`config` shape. The install itself needs a live root Ubuntu box, so it has no automated coverage - see the root README's [Tests](../README.md#tests).
