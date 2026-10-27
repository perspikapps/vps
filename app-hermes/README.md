<!-- @format -->

# app-hermes

Hermes Agent (self-improving AI agent harness), installed with helm from this repo's [`charts/hermes`](../charts/hermes/README.md) (an opt-in step).

Part of [`vps`](https://github.com/perspikapps/vps) · order 11 · opt-in · needs root, Ubuntu · needs step `svc-k3s` · [how steps work](../README.md#contributing).

## Usage

```bash
sudo vps-setup --with-app-hermes      # add it to a full run
sudo vps-setup --only-app-hermes      # just this step
sudo vps-setup --down-app-hermes      # remove it
sudo zz-setup ./ -o app-hermes         # without vps-setup, from a checkout
```

The step is a thin wrapper over [`app-helm`](../app-helm/README.md): it builds the chart values (a shared domain from `vps-network access-domain`, the app's own settings) and runs `app-helm up hermes`. Build and push the image first (`charts/hermes/README.md`); the step only installs the chart.

## Public or internal

The route is **public** (server IP) or **internal** (the internal network only), never both: `config.visibility` is the default, the system config (`vps-access`, or `SYSTEM_INTERNAL_APPS` / `SYSTEM_PUBLIC_APPS`) overrides it. For an internal route `app-helm` sets the chart's `ingress.middlewares` to the shared `internal-only` Traefik middleware (`vps-network access-route`, see `svc-k3s`).

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `HERMES_IMAGE_REPOSITORY` | yes | _(unset)_ | Image repository of the Hermes Agent image you built and pushed (no official image exists) |
| `HERMES_IMAGE_TAG` | no | `latest` | Image tag |
| `HERMES_ENV_SECRET` | no | _(unset)_ | Name of a Secret (namespace hermes) whose keys become the container environment: LLM provider and chat tokens |

## Removing (`down`)

Uninstalls the Helm release and deletes the `hermes` namespace (`app-helm down`).

## Dependencies

`svc-k3s` (kubectl and helm).

## Tests

```bash
bats test.bats
```
