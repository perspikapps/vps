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

5. Waits for Coder, then (through a port-forward, so neither DNS nor Traefik is involved) creates the **first admin** and the **`devcontainer` template**, both once: the admin's password is generated and saved to `/root/.vps-secrets.env` (shown in the final summary), and the template is the Kubernetes + [envbuilder](https://github.com/coder/envbuilder) devcontainer starter embedded in the server's own `coder` binary (so it matches the installed version), pushed with `namespace=coder` and `use_kubeconfig=false`. Workspaces build their `devcontainer.json` repo in a pod, without Docker. A re-run keeps the admin and does not push the template again; if the admin's password was changed in the UI the template step is skipped with a warning. Both steps are best effort: on failure the install still succeeds and you finish in the UI.

`CODER_ACCESS_URL` and `CODER_WILDCARD_ACCESS_URL` are set from that same domain on purpose: Coder scopes its session cookie to the wildcard domain, so reaching the dashboard on a host outside it (or on another port) ends in a cookie error at login.

**Public by design:** Traefik's 80/443 are the VPS's public ingress, so Coder is reachable from the internet like any ingress app (the step has no private port). Plain HTTP only unless you front it with TLS and set `CODER_ACCESS_URL` to the `https://` URL; Let's Encrypt cannot issue a certificate for a nip.io name or a wildcard over HTTP-01.

The Marketplace's [`charts/coder`](../charts/coder/README.md) is the Rancher-UI route to the same upstream chart; do not install both.

## Workspace templates: use Kubernetes, not Docker

Coder runs as a pod on k3s (containerd), so there is no Docker daemon or `/var/run/docker.sock` for it. The **Docker** starter template fails at its first resource with `failed to create Docker client ... Cannot connect to the Docker daemon` (`docker_volume`). Create workspaces from a Kubernetes-based template instead: the step already creates `devcontainer`, or use Templates > Create > Starter templates > Kubernetes, which runs them as pods in the cluster, with these variables:

- `use_kubeconfig = false` (use the pod's own service account, not a kubeconfig);
- `namespace = coder` (the chart's service account may create pods and volume claims in its own namespace).

Do not mount a Docker socket into the Coder pod: there is no Docker on this node. A host with Docker (`vps-dokploy`) is the other route, and it is exclusive with k3s.

## Dev container templates

After the admin exists, the step pushes one workspace template (once; an existing one is left as is):

- **`kubernetes-devcontainer` via [devcontainer-builder](https://deepspacecartel.github.io/devcontainer-builder/getting-started/platform/)**, when `DEVCONTAINER_REGISTRY_USER`, `DEVCONTAINER_REGISTRY_ORG`, `DEVCONTAINER_REGISTRY_TOKEN` **and both pins** are set. It installs the devcontainer-builder chart (with its own BuildKit, in a `devcontainer-builder` namespace labelled Pod Security `privileged`, which BuildKit requires) mapping `github.com` repos to `<DEVCONTAINER_REGISTRY>/<DEVCONTAINER_REGISTRY_ORG>`, creates the `devcontainer-images` pull secret in the `coder` namespace, then pushes that project's `templates/coder-kubernetes` with `namespace=coder`, the in-cluster builder endpoint and the pull secret. Developers then create a workspace from a git repository and branch.
- **`devcontainer` (Envbuilder starter)** otherwise, following [Add Envbuilder to a template](https://coder.com/docs/admin/integrations/devcontainers/envbuilder/add-envbuilder): the starter embedded in the server's own `coder` binary, with `namespace=coder` and `use_kubeconfig=false`.

devcontainer-builder is third-party code (a chart that runs a privileged BuildKit and holds the registry token, and a Terraform template), so it is **pinned**: `DEVCONTAINER_BUILDER_VERSION` is the chart version and `DEVCONTAINER_BUILDER_REF` the template repo's tag or commit. With credentials but no pins the step warns and uses the Envbuilder starter; nothing is taken from a default branch. The registry token needs to push and pull (GHCR: `write:packages`).

```bash
sudo ZZ_SETUP_REF=<ref> DEVCONTAINER_REGISTRY_USER=<user> DEVCONTAINER_REGISTRY_ORG=<org> \
  DEVCONTAINER_REGISTRY_TOKEN=<token> DEVCONTAINER_BUILDER_VERSION=<chart-version> DEVCONTAINER_BUILDER_REF=<tag> \
  zz-setup perspikapps/vps -o vps-coder
```

Private repositories need a Coder external auth provider with the ID `github` and the template pushed with `--var external_auth_id=github` (not done here). Subdomain apps rely on the wildcard access URL above. If a push warns, run `coder templates push` by hand.

## Removing (`down`)

```bash
sudo vps-setup --down-vps-coder
```

Deletes the `coder` namespace, **including the PostgreSQL volume: all Coder data is lost.** Also forgets the saved database and admin passwords (devcontainer-builder and its namespace are left in place).

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `CODER_ADMIN_EMAIL` | no | `admin@<wildcard domain>` | Email of the first Coder admin |
| `CODER_ADMIN_PASSWORD` | no | _(generated)_ | Password of the first Coder admin |
| `CODER_ADMIN_USERNAME` | no | `admin` | Username of the first Coder admin |
| `CODER_ACCESS_URL` | no | `http://coder.<wildcard domain>` | Externally reachable URL of Coder (its host is the Ingress host) |
| `CODER_CHART_VERSION` | no | _(latest)_ | Pin the Coder chart version (e.g. `2.37.4` stable) |
| `DEVCONTAINER_BUILDER_REF` | no | _(unset)_ | Pinned tag/commit of devcontainer-builder's Coder template (required with the registry credentials) |
| `DEVCONTAINER_BUILDER_VERSION` | no | _(unset)_ | Pinned devcontainer-builder chart version (required with the registry credentials) |
| `DEVCONTAINER_REGISTRY` | no | `ghcr.io` | Registry devcontainer-builder pushes images to |
| `DEVCONTAINER_REGISTRY_ORG` | no | _(unset)_ | Registry org/user images are pushed under |
| `DEVCONTAINER_REGISTRY_TOKEN` | no | _(unset)_ | Registry token able to push and pull (with user, org and the pins it enables devcontainer-builder) |
| `DEVCONTAINER_REGISTRY_USER` | no | _(unset)_ | Registry username for the token |
| `CODER_DB_PASSWORD` | no | _(generated)_ | PostgreSQL password for Coder |
| `CODER_DB_STORAGE` | no | `10Gi` | PostgreSQL volume size |

## Dependencies

`vps-rancher` (which brings `vps-k3s`) and `vps-common`.

## Not verified on a live host

- The devcontainer-builder chart's value names (`buildkit.deploy.enabled`, `registryAuth`, `registryMapping`) and the `coder-kubernetes` template's variable names, both taken from its setup page and not read at source; the token's push/pull scope.
- The admin and template bootstrap: the `/users/first` and `/users/login` API shapes, the `kubernetes-devcontainer` id, the `use_kubeconfig`/`namespace` variable names, and whether the template needs more (such as a cache repository).
- The guide's `bitnamilegacy/postgresql` image override needs `global.security.allowInsecureImages=true` on recent Bitnami charts (set here).
- The chart's `ingress.enable`/`className`/`host`/`wildcardHost` value names.
- That the login cookie error was fully explained by the host/wildcard mismatch: inferred from Coder's wildcard docs, not reproduced.

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape and the `package.json` shape. The install needs a live cluster.
