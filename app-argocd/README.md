<!-- @format -->

# app-argocd

ArgoCD (GitOps continuous delivery), installed with helm from this repo's [`charts/argocd`](../charts/argocd/README.md) (an opt-in step).

Part of [`vps`](https://github.com/perspikapps/vps) · order 9 · opt-in · needs root, Ubuntu · needs step `svc-k3s` · [how steps work](../README.md#contributing).

## Usage

```bash
sudo vps-setup --with-app-argocd      # add it to a full run
sudo vps-setup --only-app-argocd      # just this step
sudo vps-setup --down-app-argocd      # remove it
sudo zz-setup ./ -o app-argocd         # without vps-setup, from a checkout
```

The step is a thin wrapper over [`app-helm`](../app-helm/README.md): it builds the chart values (a shared domain from `vps-network access-domain`, the app's own settings) and runs `app-helm up argocd`. Log in as `admin`; the initial password is in the `argocd-initial-admin-secret` Secret of the `argocd` namespace.

## Public or internal

The route is **public** (server IP) or **internal** (the internal network only), never both: `config.visibility` is the default, the system config (`vps-access`, or `SYSTEM_INTERNAL_APPS` / `SYSTEM_PUBLIC_APPS`) overrides it. For an internal route `app-helm` sets the chart's `ingress.middlewares` to the shared `internal-only` Traefik middleware (`vps-network access-route`, see `svc-k3s`).

## Environment variables

None.

## Removing (`down`)

Uninstalls the Helm release and deletes the `argocd` namespace (`app-helm down`).

## Dependencies

`svc-k3s` (kubectl and helm).

## Tests

```bash
bats test.bats
```
