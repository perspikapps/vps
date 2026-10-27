<!-- @format -->

# app-epinio

Epinio (deploy apps from source), installed with helm from this repo's [`charts/epinio`](../charts/epinio/README.md) (an opt-in step).

Part of [`vps`](https://github.com/perspikapps/vps) · order 12 · opt-in · needs root, Ubuntu · needs step `svc-k3s` · [how steps work](../README.md#contributing).

## Usage

```bash
sudo vps-setup --with-app-epinio      # add it to a full run
sudo vps-setup --only-app-epinio      # just this step
sudo vps-setup --down-app-epinio      # remove it
sudo zz-setup ./ -o app-epinio         # without vps-setup, from a checkout
```

The step is a thin wrapper over [`app-helm`](../app-helm/README.md): it builds the chart values (a shared domain from `vps-network access-domain`, the app's own settings) and runs `app-helm up epinio`. Epinio brings its own Ingresses (`epinio.<domain>`, `auth.<domain>`, one host per pushed app) and certificates (cert-manager issuer `epinio-ca`), so it is public-only: no public/internal choice.

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `EPINIO_ADMIN_PASSWORD` | no | _(unset)_ | Epinio admin password (generated and saved when empty) |
| `ZZ_SECRETS_FILE` | no | `/root/.vps-secrets.env` | Owner-only env file holding the credentials the steps generate |

## Removing (`down`)

Uninstalls the Helm release and deletes the `epinio` namespace (`app-helm down`).
Forgets the saved `EPINIO_ADMIN_PASSWORD` from the secrets file.

## Dependencies

`svc-k3s` (kubectl and helm).

## Tests

```bash
bats test.bats
```
