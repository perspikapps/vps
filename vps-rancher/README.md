<!-- @format -->

# vps-rancher

Rancher install.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `dispatch.sh`'s install sequence (order `5`, enabled by default). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

Runs as one step of a full `dispatch.sh` install/removal, or standalone once `vps-common/run.sh` is reachable (see the root README's [Layout](../README.md#layout)):

```bash
sudo sh dispatch.sh --only-vps-rancher
```

Or directly, from a checkout (`up` is the default action):

```bash
sudo bash vps-rancher/run.sh up
sudo bash vps-rancher/run.sh down
```

## Removing (`down`)

`down` removes the Helm release and its namespace. Leaves cert-manager in place (shared with the Marketplace's cert-manager-dependent charts).

```bash
sudo sh dispatch.sh --down-vps-rancher
```

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `CERT_MANAGER_VERSION` | no | _(unset)_ | Pin cert-manager's chart version |
| `RANCHER_BOOTSTRAP_PASSWORD` | no | _(unset)_ | Initial admin password |
| `RANCHER_CHART_VERSION` | no | _(unset)_ | Pin a chart version |
| `RANCHER_HOSTNAME` | no | _(unset)_ | FQDN/IP used in Rancher's self-signed cert |
| `RANCHER_HTTPS_PORT` | no | `7083` | Rancher HTTPS port |
| `RANCHER_HTTP_PORT` | no | `7080` | Rancher HTTP port |

## Outputs

| Output | Description |
| --- | --- |
| `RANCHER_BOOTSTRAP_PASSWORD_FILE` | Path to the saved Rancher bootstrap password (/root/.rancher-bootstrap-password) |

## Dependencies

`vps-common` (shared helpers), plus `vps-k3s` (see this folder's `package.json` `dependencies`). `dispatch.sh` auto-enables these when this step is enabled - see the root README's [Dependencies between steps](../README.md#dependencies-between-steps).

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz_use`/`vps-common` wiring, `up()`/`down()`, and `dispatch_action`) plus `package.json`'s `bin`/`vps` fields. The step itself (a live apt/Helm/k3s install) needs a real root Ubuntu box to actually run - see the root README's [Tests](../README.md#tests) section for the full picture.
