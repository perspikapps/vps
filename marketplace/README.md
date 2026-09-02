<!-- @format -->

# marketplace

Rancher Apps & Marketplace catalog registration.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one
step in `dispatch.sh`'s install sequence (order `7`,
enabled by default). See the root
README's [One folder per feature](../README.md#one-folder-per-feature)
for the full convention this folder follows.

## Usage

Registers this repo's Helm chart catalog (`charts/`, published via
GitHub Pages - see [`.github/workflows/publish-charts.yml`](../.github/workflows/publish-charts.yml))
as a Rancher Apps \& Marketplace repository, so ArgoCD, Epinio, and any
other chart this repo publishes can be installed from Rancher's UI
instead of a dedicated per-app feature folder.

```bash
sudo sh dispatch.sh --only-marketplace
```

Or directly, from a checkout (`up` is the default action):

```bash
sudo bash marketplace/run.sh up
sudo bash marketplace/run.sh down
```

## Removing (`down`)

`down` removes the registered `ClusterRepo` from Rancher. Apps already
installed from that catalog (e.g. ArgoCD, Epinio) are left untouched.

```bash
sudo sh dispatch.sh --down-marketplace
```

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `MARKETPLACE_REPO_NAME` | no | `perspikapps-vps` | Name the catalog is registered under in Rancher |
| `MARKETPLACE_REPO_URL` | no | `https://perspikapps.github.io/vps/` | URL of the published Helm chart catalog |

## Dependencies

`common` (shared helpers), plus `rancher` (see this folder's `package.json`
`dependencies`) - the catalog is registered as a Rancher `ClusterRepo`
custom resource, so Rancher itself must already be installed.
`dispatch.sh` auto-enables these when this step is enabled - see the root
README's [Dependencies between steps](../README.md#dependencies-between-steps).

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz_use`/`common` wiring,
`up()`/`down()`, and `dispatch_action`) plus `package.json`'s `bin`/`vps`
fields. Actually registering the catalog needs a live k3s/Rancher cluster
to test - see the root README's [Tests](../README.md#tests) section for
the full picture.
