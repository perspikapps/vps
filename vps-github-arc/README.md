<!-- @format -->

# vps-github-arc

GitHub Actions Runner Controller (ARC) install.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `vps-setup`'s install sequence (order `9`, **opt-in, off by default**). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows, and [GitHub Actions Runner Controller (ARC)](../README.md#github-actions-runner-controller-arc) for the full write-up.

## Usage

Runs as one step of a full `vps-setup` install/removal, or standalone once `vps-common/run.sh` is reachable (see the root README's [Layout](../README.md#layout)). Being opt-in, it needs `--with-vps-github-arc` or `--only-vps-github-arc` explicitly - a plain `vps-setup` skips it:

```bash
sudo GITHUB_ARC_CONFIG_URL=https://github.com/perspikapps/vps \
    GITHUB_ARC_APP_ID=123456 \
    GITHUB_ARC_APP_INSTALLATION_ID=78901234 \
    GITHUB_ARC_APP_PRIVATE_KEY_FILE=/root/github-arc-app.private-key.pem \
    vps-setup --only-vps-github-arc
```

Or directly, from a checkout (`up` is the default action):

```bash
sudo bash vps-github-arc/run.sh up
sudo bash vps-github-arc/run.sh down
```

Installs both official Helm charts - the controller (`gha-runner-scale-set-controller`) and a runner scale set (`gha-runner-scale-set`) - into a single `github` namespace on the k3s cluster, authenticated via a GitHub App (create it yourself first, following [the ARC quickstart](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/get-started)).

## Removing (`down`)

`down` removes both Helm releases, the GitHub App secret, and the `github` namespace.

```bash
sudo vps-setup --down-vps-github-arc
```

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `GITHUB_ARC_CONFIG_URL` | yes | _(unset)_ | Org or repo URL runners register against |
| `GITHUB_ARC_APP_ID` | yes | _(unset)_ | GitHub App ID |
| `GITHUB_ARC_APP_INSTALLATION_ID` | yes | _(unset)_ | GitHub App installation ID |
| `GITHUB_ARC_APP_PRIVATE_KEY_FILE` | yes | _(unset)_ | Path to the GitHub App's private key PEM file |
| `GITHUB_ARC_RUNNER_SCALE_SET_NAME` | no | `arc-runner-set` | Name of the runner scale set |
| `GITHUB_ARC_MIN_RUNNERS` | no | `0` | Minimum idle runners |
| `GITHUB_ARC_MAX_RUNNERS` | no | `5` | Maximum runners |
| `GITHUB_ARC_CONTROLLER_CHART_VERSION` | no | _(latest)_ | Pin the controller chart version |
| `GITHUB_ARC_RUNNER_SET_CHART_VERSION` | no | _(latest)_ | Pin the runner scale set chart version |
| `GITHUB_ARC_INSTALL_TIMEOUT` | no | `10m` | How long to wait for each Helm install |

## Dependencies

`vps-common` (shared helpers), `vps-k3s` (the cluster runners are installed onto). `vps-setup` auto-enables these when this step is enabled - see the root README's [Dependencies between steps](../README.md#dependencies-between-steps).

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz_use`/`vps-common` wiring, `up()`/`down()`, and `dispatch_action`) plus `package.json`'s `bin`/`vps` fields. The step itself (a live Helm install against a k3s cluster) needs a real root Ubuntu box to actually run - see the root README's [Tests](../README.md#tests) section for the full picture.
