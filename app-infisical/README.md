<!-- @format -->

# app-infisical

Infisical (secrets management), installed with helm from this repo's [`charts/infisical`](../charts/infisical/README.md) (an opt-in step).

Part of [`vps`](https://github.com/perspikapps/vps) · order 14 · opt-in · needs root, Ubuntu · needs step `svc-k3s` · [how steps work](../README.md#contributing).

## Usage

```bash
sudo vps-setup --with-app-infisical      # add it to a full run
sudo vps-setup --only-app-infisical      # just this step
sudo vps-setup --down-app-infisical      # remove it
sudo zz-setup ./ -o app-infisical         # without vps-setup, from a checkout
```

The step is a thin wrapper over [`app-helm`](../app-helm/README.md): it builds the chart values (a shared domain from `vps-network access-domain`, the app's own settings) and runs `app-helm up infisical`. Infisical brings its own nginx Ingress controller (class `infisical-nginx`) and Postgres/Redis, so it is public-only at `http://infisical.<external domain>`. The step creates the required `infisical-secrets` Secret (random keys, saved to `ZZ_SECRETS_FILE`).

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `ZZ_SECRETS_FILE` | no | `/root/.vps-secrets.env` | Owner-only env file holding the credentials the steps generate |

## Removing (`down`)

Uninstalls the Helm release and deletes the `infisical` namespace (`app-helm down`).
Forgets the saved `INFISICAL_ENCRYPTION_KEY`, `INFISICAL_AUTH_SECRET` from the secrets file.

## Dependencies

`svc-k3s` (kubectl and helm).

## Tests

```bash
bats test.bats
```
