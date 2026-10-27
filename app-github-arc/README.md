<!-- @format -->

# app-github-arc

GitHub Actions Runner Controller and a runner scale set, installed with helm from this repo's [`charts/github-arc`](../charts/github-arc/README.md) (an opt-in step).

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `vps-setup`'s install sequence (order and default: `config` in its `package.json`). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

```bash
sudo vps-setup --with-app-github-arc
sudo vps-setup --only-app-github-arc
sudo vps-setup --down-app-github-arc
```

The step is a thin wrapper over [`app-helm`](../app-helm/README.md): it builds the chart values (a shared domain from `vps-network access-domain`, the app's own settings) and runs `app-helm up github-arc`. Create the GitHub App first (the ARC quickstart linked from `charts/github-arc/Chart.yaml`). The runners have no web UI, so there is no URL.

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `GITHUB_ARC_CONFIG_URL` | yes | _(unset)_ | Org or repo URL the runners register against (e.g. https://github.com/<org>) |
| `GITHUB_ARC_APP_ID` | yes | _(unset)_ | GitHub App id used to register the runners |
| `GITHUB_ARC_APP_INSTALLATION_ID` | yes | _(unset)_ | Installation id of that GitHub App |
| `GITHUB_ARC_APP_PRIVATE_KEY` | yes | _(unset)_ | Private key of that GitHub App (PEM contents) |
| `ZZ_SECRETS_FILE` | no | `/root/.vps-secrets.env` | Owner-only env file holding the credentials the steps generate |

## Dependencies

`svc-k3s` (kubectl and helm).

## Tests

```bash
bats test.bats
```
