<!-- @format -->

# app-cognee

Cognee (AI memory engine), installed with helm from this repo's [`charts/cognee`](../charts/cognee/README.md) (an opt-in step).

Part of [`vps`](https://github.com/tomgrv/vps) · order 10 · opt-in · needs root, Ubuntu · needs step `svc-k3s` · [how steps work](../README.md#contributing).

## Usage

```bash
sudo vps-setup --with-app-cognee      # add it to a full run
sudo vps-setup --only-app-cognee      # just this step
sudo vps-setup --down-app-cognee      # remove it
sudo zz-setup ./ -o app-cognee         # without vps-setup, from a checkout
```

The step is a thin wrapper over [`app-helm`](../app-helm/README.md): it builds the chart values (a shared domain from `vps-network access-domain`, the app's own settings) and runs `app-helm up cognee`. The key is saved to `ZZ_SECRETS_FILE` and given to the chart through a values file, never `--set`.

## Public or internal

The route is **public** (server IP) or **internal** (the internal network only), never both: `config.visibility` is the default, the system config (`vps-access`, or `SYSTEM_INTERNAL_APPS` / `SYSTEM_PUBLIC_APPS`) overrides it. For an internal route `app-helm` sets the chart's `ingress.middlewares` to the shared `internal-only` Traefik middleware (`vps-network access-route`, see `svc-k3s`).

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `COGNEE_LLM_API_KEY` | yes | _(unset)_ | LLM provider API key Cognee needs to start (OpenAI by default) |
| `ZZ_SECRETS_FILE` | no | `/root/.vps-secrets.env` | Owner-only env file holding the credentials the steps generate |

## Removing (`down`)

Uninstalls the Helm release and deletes the `cognee` namespace (`app-helm down`).
Forgets the saved `COGNEE_LLM_API_KEY` from the secrets file.

## Dependencies

`svc-k3s` (kubectl and helm).

## Tests

```bash
bats test.bats
```
