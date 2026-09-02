<!-- @format -->

# epinio

Epinio install.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `dispatch.sh`'s install sequence (order `8`, opt-in by default). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

Runs as one step of a full `dispatch.sh` install/removal, or standalone once `common/run.sh` is reachable (see the root README's [Layout](../README.md#layout)):

```bash
sudo sh dispatch.sh --only-epinio
```

Or directly, from a checkout (`up` is the default action):

```bash
sudo bash epinio/run.sh up
sudo bash epinio/run.sh down
```

## Removing (`down`)

`down` removes the Helm release, its namespace, and the `epinio` CLI. Leaves k3s, cert-manager, and Traefik in place.

```bash
sudo sh dispatch.sh --down-epinio
```

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `CERT_MANAGER_VERSION` | no | _(unset)_ | Pin cert-manager's chart version |
| `EPINIO_ADMIN_PASSWORD` | no | _(unset)_ | Admin login password |
| `EPINIO_CHART_VERSION` | no | _(unset)_ | Pin a chart version |
| `EPINIO_DOMAIN` | no | _(unset)_ | Wildcard domain Epinio's Ingresses use |
| `EPINIO_INGRESS_CLASS` | no | `traefik` | IngressClass to pin Epinio's Ingresses to |
| `EPINIO_INSTALL_TIMEOUT` | no | `15m` | How long to wait for all pods to come up |
| `EPINIO_TLS_ISSUER` | no | `epinio-ca` | cert-manager ClusterIssuer for Epinio's certs |

## Outputs

| Output | Description |
| --- | --- |
| `EPINIO_ADMIN_PASSWORD_FILE` | Path to the saved Epinio admin password (/root/.epinio-admin-password) |

## Dependencies

`common` (shared helpers), plus `k3s` (see this folder's `package.json` `dependencies`). `dispatch.sh` auto-enables these when this step is enabled - see the root README's [Dependencies between steps](../README.md#dependencies-between-steps).

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz_use`/`common` wiring, `up()`/`down()`, and `dispatch_action`) plus `package.json`'s `bin`/`vps` fields. The step itself (a live apt/Helm/k3s install) needs a real root Ubuntu box to actually run - see the root README's [Tests](../README.md#tests) section for the full picture.
