<!-- @format -->

# vps-dockermanager

cockpit-packagekit/files/dockermanager install.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `vps-setup`'s install sequence (order `6`, enabled by default). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

Runs as one step of a full `vps-setup` install/removal, or standalone once `vps-common/run.sh` is reachable (see the root README's [Layout](../README.md#layout)):

```bash
sudo vps-setup --only-vps-dockermanager
```

Or directly, from a checkout (`up` is the default action):

```bash
sudo bash vps-dockermanager/run.sh up
sudo bash vps-dockermanager/run.sh down
```

## Removing (`down`)

`down` removes cockpit-dockermanager, cockpit-packagekit, and cockpit-files. Leaves Docker itself installed unless `REMOVE_DOCKER=true`.

```bash
sudo vps-setup --down-vps-dockermanager
```

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `COCKPIT_DOCKERMANAGER_VERSION` | no | `latest` | cockpit-dockermanager release tag to install |
| `INSTALL_DOCKER` | no | `true` | Install docker.io if no docker daemon is present already (true/false) |
| `REMOVE_DOCKER` | no | `false` | Also remove Docker itself on down (true/false) |

## Dependencies

`vps-common` (shared helpers), plus `vps-cockpit` (see this folder's `package.json` `dependencies`). `vps-setup` auto-enables these when this step is enabled - see the root README's [Dependencies between steps](../README.md#dependencies-between-steps).

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz_use`/`vps-common` wiring, `up()`/`down()`, and `dispatch_action`) plus `package.json`'s `bin`/`vps` fields. The step itself (a live apt/Helm/k3s install) needs a real root Ubuntu box to actually run - see the root README's [Tests](../README.md#tests) section for the full picture.
