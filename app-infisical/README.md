<!-- @format -->

# app-infisical

Infisical (secrets management), installed with helm from this repo's [`charts/infisical`](../charts/infisical/README.md) (an opt-in step).

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `vps-setup`'s install sequence (order and default: `config` in its `package.json`). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

```bash
sudo vps-setup --with-app-infisical
sudo vps-setup --only-app-infisical
sudo vps-setup --down-app-infisical
```

The step is a thin wrapper over [`app-helm`](../app-helm/README.md): it builds the chart values (a shared domain from `vps-network access-domain`, the app's own settings) and runs `app-helm up infisical`. Infisical brings its own nginx Ingress controller (class `infisical-nginx`) and Postgres/Redis, so it is public-only at `http://infisical.<external domain>`. The step creates the required `infisical-secrets` Secret (random keys, saved to `SYSTEM_SECRETS_FILE`).

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `SYSTEM_SECRETS_FILE` | no | `/root/.vps-secrets.env` | Owner-only env file holding the credentials the steps generate |

## Dependencies

`vps-k3s` (kubectl and helm).

## Tests

```bash
bats test.bats
```
