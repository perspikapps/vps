<!-- @format -->

# system

Base system update & essentials.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `dispatch.sh`'s install sequence (order `0`, enabled by default). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

Runs as one step of a full `dispatch.sh` install/removal, or standalone once `common/run.sh` is reachable (see the root README's [Layout](../README.md#layout)):

```bash
sudo sh dispatch.sh --only-system
```

Or directly, from a checkout (`up` is the default action):

```bash
sudo bash system/run.sh up
```

## Removing (`down`)

This step has no `down` action - it's a one-shot base package upgrade, nothing to undo. Running `up` again is always safe (idempotent).

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `TZ` | no | _(unset)_ | Timezone to set on the VPS (e.g. Europe/Paris) |

## Dependencies

`common` (shared helpers). `dispatch.sh` auto-enables these when this step is enabled - see the root README's [Dependencies between steps](../README.md#dependencies-between-steps).

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz_use`/`common` wiring, `up()`, and `dispatch_action`) plus `package.json`'s `bin`/`vps` fields. The step itself (a live apt/Helm/k3s install) needs a real root Ubuntu box to actually run - see the root README's [Tests](../README.md#tests) section for the full picture.
