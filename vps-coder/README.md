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
4. Installs the upstream `coder` chart behind an **Ingress on k3s's Traefik** (class `traefik`, ports 80/443): host `coder.<wildcard domain>` for the dashboard and `*.<wildcard domain>` for workspace apps. The domain is `vps-system`'s `WILDCARD_DOMAIN`, else nip.io (`coder.54-37-230-112.nip.io`).

`CODER_ACCESS_URL` and `CODER_WILDCARD_ACCESS_URL` are set from that same domain on purpose: Coder scopes its session cookie to the wildcard domain, so reaching the dashboard on a host outside it (or on another port) ends in a cookie error at login.

**Public by design:** Traefik's 80/443 are the VPS's public ingress, so Coder is reachable from the internet like any ingress app (the step has no private port). Plain HTTP only unless you front it with TLS and set `CODER_ACCESS_URL` to the `https://` URL; Let's Encrypt cannot issue a certificate for a nip.io name or a wildcard over HTTP-01.

The Marketplace's [`charts/coder`](../charts/coder/README.md) is the Rancher-UI route to the same upstream chart; do not install both.

## Workspace templates: use Kubernetes, not Docker

Coder runs as a pod on k3s (containerd), so there is no Docker daemon or `/var/run/docker.sock` for it. The **Docker** starter template fails at its first resource with `failed to create Docker client ... Cannot connect to the Docker daemon` (`docker_volume`). Create workspaces from the **Kubernetes** starter template instead (Templates > Create > Starter templates > Kubernetes), which runs them as pods in the cluster, with these variables:

- `use_kubeconfig = false` (use the pod's own service account, not a kubeconfig);
- `namespace = coder` (the chart's service account may create pods and volume claims in its own namespace).

Do not mount a Docker socket into the Coder pod: there is no Docker on this node. A host with Docker (`vps-dokploy`) is the other route, and it is exclusive with k3s.

## Removing (`down`)

```bash
sudo vps-setup --down-vps-coder
```

Deletes the `coder` namespace, **including the PostgreSQL volume: all Coder data is lost.** Also forgets the saved database password.

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `CODER_ACCESS_URL` | no | `http://coder.<wildcard domain>` | Externally reachable URL of Coder (its host is the Ingress host) |
| `CODER_CHART_VERSION` | no | _(latest)_ | Pin the Coder chart version (e.g. `2.37.4` stable) |
| `CODER_DB_PASSWORD` | no | _(generated)_ | PostgreSQL password for Coder |
| `CODER_DB_STORAGE` | no | `10Gi` | PostgreSQL volume size |

## Dependencies

`vps-rancher` (which brings `vps-k3s`) and `vps-common`.

## Not verified on a live host

The guide's `bitnamilegacy/postgresql` image override needs `global.security.allowInsecureImages=true` on recent Bitnami charts (set here); the chart's `ingress.enable`/`className`/`host`/`wildcardHost` values and that the cookie error is fully explained by the host/wildcard mismatch (the cause is inferred from Coder's wildcard docs, not reproduced) and the rebind are assumed from the upstream chart.

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape and the `package.json` shape. The install needs a live cluster.
