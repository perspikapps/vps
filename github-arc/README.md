<!-- @format -->

# github-arc

GitHub Actions Runner Controller (ARC) install.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `dispatch.sh`'s install sequence (order `9`, opt-in by default). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

Runs as one step of a full `dispatch.sh` install/removal, or standalone once `common/run.sh` is reachable (see the root README's [Layout](../README.md#layout)):

```bash
sudo sh dispatch.sh --only-github-arc
```

Or directly, from a checkout (`up` is the default action):

```bash
sudo bash github-arc/run.sh up
sudo bash github-arc/run.sh down
```

## Removing (`down`)

`down` removes both Helm releases (controller and runner scale set), the GitHub App secret, and the `github` namespace. Leaves k3s in place.

```bash
sudo sh dispatch.sh --down-github-arc
```

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `GITHUB_ARC_APP_ID` | yes | _(unset)_ | GitHub App ID |
| `GITHUB_ARC_APP_INSTALLATION_ID` | yes | _(unset)_ | GitHub App installation ID |
| `GITHUB_ARC_APP_PRIVATE_KEY_FILE` | yes | _(unset)_ | Path to the GitHub App's private key PEM file |
| `GITHUB_ARC_CONFIG_URL` | yes | _(unset)_ | Org or repo URL runners register against |
| `GITHUB_ARC_CONTROLLER_CHART_VERSION` | no | _(unset)_ | Pin the controller chart version |
| `GITHUB_ARC_INSTALL_TIMEOUT` | no | `10m` | How long to wait for each helm install |
| `GITHUB_ARC_MAX_RUNNERS` | no | `5` | Maximum runners |
| `GITHUB_ARC_MIN_RUNNERS` | no | `0` | Minimum idle runners |
| `GITHUB_ARC_RUNNER_SCALE_SET_NAME` | no | `arc-runner-set` | Name of the runner scale set |
| `GITHUB_ARC_RUNNER_SET_CHART_VERSION` | no | _(unset)_ | Pin the runner scale set chart version |

## Dependencies

`common` (shared helpers), plus `k3s` (see this folder's `package.json` `dependencies`). `dispatch.sh` auto-enables these when this step is enabled - see the root README's [Dependencies between steps](../README.md#dependencies-between-steps).

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz_use`/`common` wiring, `up()`/`down()`, and `dispatch_action`) plus `package.json`'s `bin`/`vps` fields. The step itself (a live apt/Helm/k3s install) needs a real root Ubuntu box to actually run - see the root README's [Tests](../README.md#tests) section for the full picture.
