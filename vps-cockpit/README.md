<!-- @format -->

# vps-cockpit

Cockpit install.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `vps-setup`'s install sequence (order and default: `config` in its `package.json`). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

Runs as one step of a full `vps-setup` install/removal, or standalone once `vps-common/run.sh` is reachable (see the root README's [Layout](../README.md#layout)):

```bash
sudo vps-setup --only-vps-cockpit
```

Or directly, from a checkout (`up` is the default action):

```bash
sudo bash vps-cockpit/run.sh up
sudo bash vps-cockpit/run.sh down
```

## Removing (`down`)

`down` removes the Cockpit packages and socket config.

```bash
sudo vps-setup --down-vps-cockpit
```

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `COCKPIT_HTTPS_PORT` | no | `9083` | Cockpit HTTPS port |
| `COCKPIT_HTTP_PORT` | no | `9080` | Cockpit HTTP port |

## Dependencies

`vps-common` (shared helpers) only; no other step is required.

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz-use`/`vps-common` wiring, `up()`/`down()`, and `dispatch_action`) plus the `package.json` `bin`/`engines`/`config` shape. The install itself needs a live root Ubuntu box, so it has no automated coverage - see the root README's [Tests](../README.md#tests).
