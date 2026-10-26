<!-- @format -->

# vps-rancher

Rancher install.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `vps-setup`'s install sequence (order and default: `config` in its `package.json`). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

Runs as one step of a full `vps-setup` install/removal, or on its own through `zz-setup`, from a checkout:

```bash
sudo vps-setup --only-vps-rancher
```

Or from a checkout, without `vps-setup` (`up` by default; `zz-setup` runs the step's `run.sh`):

```bash
sudo zz-setup ./ -o vps-rancher
sudo zz-setup ./ -d vps-rancher
```

## Public dashboard through Traefik

The dashboard is served by k3s's Traefik at `https://rancher.<domain>` (Let's Encrypt via
the `letsencrypt` resolver; staging certs until `TRAEFIK_ACME_STAGING=false`). `<domain>` is
`EXTERNAL_DOMAIN`, else `<public-ip>.nip.io`; set `RANCHER_INGRESS_HOST` to use another host.
`vps-access` (or `RANCHER_ACCESS`, which wins) picks where the route is served, **public or internal, never both**: `public` (default) is the server IP on 80/443; `internal` is `rancher.<internal-ip>.nip.io` on Traefik's private `internal`/`internalsecure` entrypoints (the UI on `TRAEFIK_INTERNAL_HTTPS_PORT`, 8444) over Tailscale/Cloudflare, with Traefik's default certificate. Rancher has no port of its own: its Service is a `ClusterIP`, reached only through Traefik. Rancher's server URL (`RANCHER_HOSTNAME`) defaults to the route's host. A public route makes the admin UI reachable from the internet, so change the bootstrap password on first login.

## Installing from SUSE Rancher Prime

Set `RANCHER_CHART_REPO_URL` to the Prime chart repository, then run the step:

```bash
sudo RANCHER_CHART_REPO_URL=https://charts.rancher.com/server-charts/prime vps-setup --only-vps-rancher
```

The URL must be an `http(s)` Helm repository; a bad URL or an unreachable index stops
the step before anything is installed. Pin a release with `RANCHER_CHART_VERSION`. Prime's
images and any subscription requirements are SUSE's: this step only changes where the
chart comes from. Switching an already-running community Rancher over by re-running the
step is an in-place `helm upgrade` to the Prime chart; check SUSE's upgrade notes for the
versions involved first.

## Chart files

The Helm values and the Traefik Ingress are YAML files in the `helm/` subfolder, not heredocs:
`helm/values.yaml` (fixed chart values, passed with `--values`; `hostname` and
`bootstrapPassword` still go in a generated second values file) and `helm/ingress.yaml`
(`${INGRESS_HOST}` is filled in by [`yaml-render`](https://github.com/tomgrv/scripts/tree/main/yaml-render)).

## Progress

The install is mostly waiting (chart download, then Rancher's images being pulled,
typically 3-8 minutes), and `helm --wait` itself prints nothing. While it waits,
the step logs a line every `PROGRESS_INTERVAL` seconds, for example:

```
Rancher install: 45s, 1/2 pods ready - waiting: rancher-2=ContainerCreating
```

(`no pod in cattle-system yet` before the first pod exists.) The same helper,
`kube-progress` (tomgrv/scripts), also covers the cert-manager install, this
step's final rollout wait and the Traefik rollout in `vps-k3s`.

## If the install fails or hangs

Rancher's Service is a `ClusterIP` (older runs left a `LoadBalancer` on private ports; the step removes it so helm recreates it). The step creates the release **without** `helm --wait` and waits for the rollout itself, with progress. When a wait still fails,
the step prints diagnostics before exiting: pods and services, recent events,
the `svclb-*` pods in `kube-system` and why each unready pod is not running.
Re-running `sudo vps-setup --only-vps-rancher` is safe: `helm upgrade --install`
replaces a failed release, and a Service left rebound by a previous run is removed
first so helm recreates it (merging the chart's ports 80/443 into the rebound ones
would give duplicate port names). Rancher's pods keep running meanwhile; only the
Service is briefly gone.

## Removing (`down`)

`down` removes the Helm release and its namespace. Leaves cert-manager in place (shared with the Marketplace's cert-manager-dependent charts).

```bash
sudo vps-setup --down-vps-rancher
```

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `VPS_SECRETS_FILE` | no | `/root/.vps-secrets.env` | Owner-only env file holding the credentials the steps generate |
| `CERT_MANAGER_VERSION` | no | _(unset)_ | Pin cert-manager's chart version |
| `RANCHER_BOOTSTRAP_PASSWORD` | no | _(unset)_ | Initial admin password |
| `RANCHER_CHART_REPO_URL` | no | `https://releases.rancher.com/server-charts/latest` | Helm repository to install Rancher from; `https://charts.rancher.com/server-charts/prime` for SUSE Rancher Prime |
| `RANCHER_CHART_VERSION` | no | _(unset)_ | Pin a chart version |
| `PROGRESS_INTERVAL` | no | `15` | Seconds between progress lines during the long waits |
| `RANCHER_ACCESS` | no | _(vps-access, else `public`)_ | `public` (server IP) or `internal` (Tailscale/Cloudflare address) for the Traefik route |
| `RANCHER_INGRESS_HOST` | no | `rancher.<domain>` | Host Traefik serves the dashboard on |
| `RANCHER_HOSTNAME` | no | the route's host | Rancher server URL host / self-signed cert name |

## Outputs

| Output | Description |
| --- | --- |
| `RANCHER_BOOTSTRAP_PASSWORD_FILE` | Owner-only env file (`/root/.vps-secrets.env`) holding `RANCHER_BOOTSTRAP_PASSWORD` (older hosts: `/root/.rancher-bootstrap-password`, migrated on the next run) |

## Dependencies

Step dependency: `vps-k3s` - `vps-setup` auto-enables it when this step is enabled (see the root README's [Dependencies between steps](../README.md#dependencies-between-steps)).

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz-use` line, the `up`/`down` dispatch, and that nothing but `zz-colors` is sourced) plus the `package.json` `bin`/`engines`/`config` shape. The install itself needs a live root Ubuntu box, so it has no automated coverage - see the root README's [Tests](../README.md#tests).
