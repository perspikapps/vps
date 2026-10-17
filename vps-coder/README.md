<!-- @format -->

# vps-coder

[Coder](https://coder.com) (remote development environments) on the k3s cluster, following [Coder's Rancher install guide](https://coder.com/docs/install/server/rancher) with the helm CLI instead of the Rancher UI.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `vps-setup`'s install sequence (order and default: `config` in its `package.json`). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

**Opt-in** (`config.default: false`); it needs `vps-rancher` (and so `vps-k3s`), which also registers the `bitnami` Helm repository.

## Usage

```bash
sudo vps-setup --with-vps-coder
sudo vps-setup --only-vps-coder   # just this step, on a host that already has Rancher
```

Or directly, from a checkout (`up` is the default action):

```bash
sudo bash vps-coder/run.sh up
sudo bash vps-coder/run.sh down
```

## What it does

1. Creates the `coder` namespace and adds the Bitnami and Coder (`https://helm.coder.com/v2`) Helm repositories.
2. Installs `coder-db` (Bitnami PostgreSQL, user/database `coder`, `CODER_DB_STORAGE` volume) with a generated password saved to `/root/.vps-secrets.env`.
3. Creates the `coder-db-url` Secret the chart reads `CODER_PG_CONNECTION_URL` from.
4. Installs the upstream `coder` chart with `CODER_ACCESS_URL` set, then rebinds its Service to the `coder_http` port (default `7100`, `access: "private"`), like `vps-rancher` does for 7080/7083.

`CODER_WILDCARD_ACCESS_URL` is set to `*.<wildcard domain>:7100` from `vps-system`'s `WILDCARD_DOMAIN`, falling back to nip.io (`*.<ip>.nip.io:7100`), for Coder's workspace apps.

`CODER_ACCESS_URL` defaults to `http://<private address>:7100`, so workspaces and users must reach that address; set it to your real URL (and put an Ingress/TLS in front) for production. Without a private network the URL has no address yet: set `CODER_ACCESS_URL`.

The Marketplace's [`charts/coder`](../charts/coder/README.md) is the Rancher-UI route to the same upstream chart; do not install both.

## Removing (`down`)

```bash
sudo vps-setup --down-vps-coder
```

Deletes the `coder` namespace, **including the PostgreSQL volume: all Coder data is lost.** Also forgets the saved database password.

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `CODER_ACCESS_URL` | no | _(private address, port 7100)_ | Externally reachable URL of Coder |
| `CODER_CHART_VERSION` | no | _(latest)_ | Pin the Coder chart version (e.g. `2.37.4` stable) |
| `CODER_DB_PASSWORD` | no | _(generated)_ | PostgreSQL password for Coder |
| `CODER_DB_STORAGE` | no | `10Gi` | PostgreSQL volume size |
| `CODER_HTTP_PORT` | no | `7100` | Port Coder is published on (private access) |

## Dependencies

`vps-rancher` (which brings `vps-k3s`) and `vps-common`.

## Not verified on a live host

The guide's `bitnamilegacy/postgresql` image override needs `global.security.allowInsecureImages=true` on recent Bitnami charts (set here); whether Coder accepts a port in the wildcard URL, the chart's Service port name `http` and the rebind are assumed from the upstream chart.

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape and the `package.json` shape. The install needs a live cluster.
