<!-- @format -->

# vps-marketplace

Rancher Apps & Marketplace catalog registration.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `vps-setup`'s install sequence (order and default: `config` in its `package.json`). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

Runs as one step of a full `vps-setup` install/removal, or on its own through `zz-setup`, from a checkout:

```bash
sudo vps-setup --only-vps-marketplace
```

Or from a checkout, without `vps-setup` (`up` by default; the step is sourced and its `up()` or `down()` called, so `run.sh` is not run directly):

```bash
sudo zz-setup ./ -o vps-marketplace
sudo zz-setup ./ -d vps-marketplace
```

## Removing (`down`)

`down` removes the `ClusterRepo` catalog registration only. Leaves any apps already installed from it (uninstall those from Rancher's UI).

```bash
sudo vps-setup --down-vps-marketplace
```

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `MARKETPLACE_REPO_NAME` | no | `perspikapps-vps` | Name of the Rancher ClusterRepo to register |
| `MARKETPLACE_REPO_URL` | no | `https://perspikapps.github.io/vps/` | URL of the Helm chart catalog to register |

## Dependencies

Step dependency: `vps-rancher` - `vps-setup` auto-enables it when this step is enabled (see the root README's [Dependencies between steps](../README.md#dependencies-between-steps)).

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz-use` line, the functions `zz-setup` calls, and that nothing but `zz-colors` is sourced) plus the `package.json` `bin`/`engines`/`config` shape. The install itself needs a live root Ubuntu box, so it has no automated coverage - see the root README's [Tests](../README.md#tests).
