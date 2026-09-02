<!-- @format -->

# argocd

ArgoCD install.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `dispatch.sh`'s install sequence (order `7`, opt-in by default). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

Runs as one step of a full `dispatch.sh` install/removal, or standalone once `common/run.sh` is reachable (see the root README's [Layout](../README.md#layout)):

```bash
sudo sh dispatch.sh --only-argocd
```

Or directly, from a checkout (`up` is the default action):

```bash
sudo bash argocd/run.sh up
sudo bash argocd/run.sh down
```

## Removing (`down`)

`down` removes the Helm release and its namespace. Leaves k3s and cert-manager in place.

```bash
sudo sh dispatch.sh --down-argocd
```

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `ARGOCD_CHART_VERSION` | no | _(unset)_ | Pin a chart version |
| `ARGOCD_HTTPS_PORT` | no | `7093` | ArgoCD HTTPS port |
| `ARGOCD_HTTP_PORT` | no | `7090` | ArgoCD HTTP port |
| `ARGOCD_INSTALL_TIMEOUT` | no | `15m` | How long to wait for all pods to come up |

## Outputs

| Output | Description |
| --- | --- |
| `ARGOCD_ADMIN_PASSWORD_FILE` | Path to the saved ArgoCD initial admin password (/root/.argocd-admin-password) |

## Dependencies

`common` (shared helpers), plus `k3s` (see this folder's `package.json` `dependencies`). `dispatch.sh` auto-enables these when this step is enabled - see the root README's [Dependencies between steps](../README.md#dependencies-between-steps).

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz_use`/`common` wiring, `up()`/`down()`, and `dispatch_action`) plus `package.json`'s `bin`/`vps` fields. The step itself (a live apt/Helm/k3s install) needs a real root Ubuntu box to actually run - see the root README's [Tests](../README.md#tests) section for the full picture.
