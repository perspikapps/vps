<!-- @format -->

# vps-system

Base system update & essentials.

Part of [`vps`](https://github.com/tomgrv/vps) · order 0 · on by default · needs root, Ubuntu · [how steps work](../README.md#contributing).

## Usage

```bash
sudo vps-setup --only-vps-system      # just this step (it is on by default)
sudo vps-setup --skip-vps-system      # leave it out of a full run
sudo vps-setup --down-vps-system      # remove it
sudo zz-setup ./ -o vps-system         # without vps-setup, from a checkout
```

## Wildcard DNS

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `SYSTEM_TZ` | no | _(unset)_ | Timezone to set on the VPS (e.g. Europe/Paris) |

## Removing (`down`)

This step has no `down` action - it's a one-shot base package upgrade, nothing to undo. Running `up` again is always safe (idempotent).

## Dependencies

No other step is required.

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz-use` line, the `up`/`down` dispatch, and that nothing but `zz-colors` is sourced) plus the `package.json` `bin`/`engines`/`config` shape. The install itself needs a live root Ubuntu box, so it has no automated coverage - see the root README's [Tests](../README.md#contributing).
