<!-- @format -->

# app-helm

Installs a chart of this repo's catalog (`charts/<app>`) with helm. A **script, not a step**: the `app-*` steps call it, and `zz-setup` puts it on `PATH`.

Part of [`tomgrv/vps`](https://github.com/tomgrv/vps).

## Usage

```sh
app-helm up|down|summary <app> [--middlewares-key <dotted.path>] [--note <text>] [helm args...]
```

| Action    | What it does                                                                                                                                       |
| --------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `up`      | checks kubectl/helm (`kube-require`), takes the route of the app from `vps-network access-route <app>`, writes a values file (`global.domain`, and the route's middlewares at `--middlewares-key` for an internal route), runs `helm dependency update` then `helm-install` |
| `down`    | `kube-teardown`: uninstalls the release and deletes its namespace                                                                                   |
| `summary` | the public / internal / local paragraph (`vps-network summary-block`) with the app's host, then the `--note` lines                                  |

Everything else on the command line goes to `helm upgrade --install` (`--values`, `--set`...). The release and namespace are named after the app (`APP_NAMESPACE` overrides the namespace); the chart is `charts/<app>` of the checkout (`ZZ_SETUP_ROOT`, or `VPS_SETUP_ROOT`).

## Tests

```sh
bats test.bats
```
