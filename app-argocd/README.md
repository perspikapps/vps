<!-- @format -->

# app-argocd

ArgoCD (GitOps continuous delivery), installed with helm from this repo's [`charts/argocd`](../charts/argocd/README.md) (an opt-in step).

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `vps-setup`'s install sequence (order and default: `config` in its `package.json`). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

```bash
sudo vps-setup --with-app-argocd
sudo vps-setup --only-app-argocd
sudo vps-setup --down-app-argocd
```

The step is a thin wrapper over [`app-helm`](../app-helm/README.md): it builds the chart values (a shared domain from `vps-network access-domain`, the app's own settings) and runs `app-helm up argocd`. Log in as `admin`; the initial password is in the `argocd-initial-admin-secret` Secret of the `argocd` namespace.

## Public or internal

The route is **public** (server IP) or **internal** (the internal network only), never both: `config.visibility` is the default, `vps-access` (or `ARGOCD_ACCESS`) overrides it. For an internal route `app-helm` sets the chart's `ingress.middlewares` to the shared `internal-only` Traefik middleware (`vps-network access-route`, see `vps-k3s`).

## Dependencies

`vps-k3s` (kubectl and helm).

## Tests

```bash
bats test.bats
```
