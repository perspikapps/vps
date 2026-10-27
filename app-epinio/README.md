<!-- @format -->

# app-epinio

Epinio (deploy apps from source), installed with helm from this repo's [`charts/epinio`](../charts/epinio/README.md) (an opt-in step).

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `vps-setup`'s install sequence (order and default: `config` in its `package.json`). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

```bash
sudo vps-setup --with-app-epinio
sudo vps-setup --only-app-epinio
sudo vps-setup --down-app-epinio
```

The step is a thin wrapper over [`app-helm`](../app-helm/README.md): it builds the chart values (a shared domain from `vps-network access-domain`, the app's own settings) and runs `app-helm up epinio`. Epinio brings its own Ingresses (`epinio.<domain>`, `auth.<domain>`, one host per pushed app) and certificates (cert-manager issuer `epinio-ca`), so it is public-only: no public/internal choice.

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `EPINIO_ADMIN_PASSWORD` | no | _(unset)_ | Epinio admin password (generated and saved when empty) |
| `SYSTEM_SECRETS_FILE` | no | `/root/.vps-secrets.env` | Owner-only env file holding the credentials the steps generate |

## Dependencies

`svc-k3s` (kubectl and helm).

## Tests

```bash
bats test.bats
```
