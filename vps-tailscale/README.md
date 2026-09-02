<!-- @format -->

# vps-tailscale

Tailscale install.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `dispatch.sh`'s install sequence (order `2`, enabled by default). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

Runs as one step of a full `dispatch.sh` install/removal, or standalone once `common/run.sh` is reachable (see the root README's [Layout](../README.md#layout)):

```bash
sudo sh dispatch.sh --only-vps-tailscale
```

Or directly, from a checkout (`up` is the default action):

```bash
sudo bash vps-tailscale/run.sh up
sudo bash vps-tailscale/run.sh down
```

## Removing (`down`)

`down` removes logs out of the tailnet and disables `tailscaled`. Leaves the `tailscale` package itself installed unless `PURGE_TAILSCALE=true`.

```bash
sudo sh dispatch.sh --down-vps-tailscale
```

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `PURGE_TAILSCALE` | no | `false` | Also remove the tailscale package on down (true/false) |
| `TAILSCALE_AUTHKEY` | yes | _(unset)_ | Auth key to auto-join a tailnet |
| `TAILSCALE_EXTRA_ARGS` | no | _(unset)_ | Extra flags appended to tailscale up |

## Dependencies

`common` (shared helpers). `dispatch.sh` auto-enables these when this step is enabled - see the root README's [Dependencies between steps](../README.md#dependencies-between-steps).

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz_use`/`common` wiring, `up()`/`down()`, and `dispatch_action`) plus `package.json`'s `bin`/`vps` fields. The step itself (a live apt/Helm/k3s install) needs a real root Ubuntu box to actually run - see the root README's [Tests](../README.md#tests) section for the full picture.
