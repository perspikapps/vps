<!-- @format -->

# app-cert-manager

Installs cert-manager (with its CRDs) through Helm into the `cert-manager` namespace
unless the deployment already exists, logging progress through `kube-progress`
(tomgrv/scripts) while it starts. A **script, not a step**: its `package.json` has a
`bin` but no `engines.zz-setup`, so `zz-setup` never lists it. `app-rancher` calls it
(by path, `$(dirname "$0")/../app-cert-manager/run.sh`).

Part of [`tomgrv/vps`](https://github.com/tomgrv/vps).

## Usage

```sh
app-cert-manager [-v version]
```

The chart version comes from `-v`, else `RANCHER_CERT_MANAGER_VERSION`, else the latest.
Needs `helm` and `kubectl` (from `svc-k3s`).

## Tests

```sh
bats test.bats
```

- does nothing when cert-manager is already installed
- installs the chart with its CRDs and the pinned version
