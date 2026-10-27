<!-- @format -->

# app-cognee

Cognee (AI memory engine), installed with helm from this repo's [`charts/cognee`](../charts/cognee/README.md) (an opt-in step).

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `vps-setup`'s install sequence (order and default: `config` in its `package.json`). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

```bash
sudo vps-setup --with-app-cognee
sudo vps-setup --only-app-cognee
sudo vps-setup --down-app-cognee
```

The step is a thin wrapper over [`app-helm`](../app-helm/README.md): it builds the chart values (a shared domain from `vps-network access-domain`, the app's own settings) and runs `app-helm up cognee`. The key is saved to `SYSTEM_SECRETS_FILE` and given to the chart through a values file, never `--set`.

## Public or internal

The route is **public** (server IP) or **internal** (the internal network only), never both: `config.visibility` is the default, the system config (`vps-access`, or `SYSTEM_INTERNAL_APPS` / `SYSTEM_PUBLIC_APPS`) overrides it. For an internal route `app-helm` sets the chart's `ingress.middlewares` to the shared `internal-only` Traefik middleware (`vps-network access-route`, see `svc-k3s`).

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `COGNEE_LLM_API_KEY` | yes | _(unset)_ | LLM provider API key Cognee needs to start (OpenAI by default) |
| `SYSTEM_SECRETS_FILE` | no | `/root/.vps-secrets.env` | Owner-only env file holding the credentials the steps generate |

## Dependencies

`svc-k3s` (kubectl and helm).

## Tests

```bash
bats test.bats
```
