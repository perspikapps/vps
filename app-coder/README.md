<!-- @format -->

# app-coder

[Coder](https://coder.com) (remote development environments) on the k3s cluster, following [Coder's Rancher install guide](https://coder.com/docs/install/server/rancher) with the helm CLI instead of the Rancher UI.

**Opt-in** (`config.default: false`); it needs `app-rancher` (and so `svc-k3s`), which also registers the `bitnami` Helm repository.

Part of [`vps`](https://github.com/tomgrv/vps) · order 8 · opt-in · needs root, Ubuntu · needs step `app-rancher` · [how steps work](../README.md#contributing).

## Usage

```bash
sudo vps-setup --with-app-coder      # add it to a full run
sudo vps-setup --only-app-coder      # just this step
sudo vps-setup --down-app-coder      # remove it
sudo zz-setup ./ -o app-coder         # without vps-setup, from a checkout
```

## What it does

1. Creates the `coder` namespace and adds the Bitnami and Coder (`https://helm.coder.com/v2`) Helm repositories.
2. Installs `coder-db` (Bitnami PostgreSQL, user/database `coder`, `CODER_DB_STORAGE` volume) with a generated password saved to `/root/.vps-secrets.env`.
3. Creates the `coder-db-url` Secret the chart reads `CODER_PG_CONNECTION_URL` from.
4. Installs the upstream `coder` chart behind an **Ingress on k3s's Traefik** (class `traefik`, ports 80/443): host `coder.<wildcard domain>` for the dashboard and `*.<wildcard domain>` for workspace apps. The domain is `vps-system`'s `SYSTEM_EXTERNAL_DOMAIN`, else nip.io (`coder.54-37-230-112.nip.io`).

5. Waits for Coder, then (through a port-forward, so neither DNS nor Traefik is involved) creates the **first admin** and the **`devcontainer` template**, both once: the admin's password is generated and saved to `/root/.vps-secrets.env` (shown in the final summary), and the template is the Kubernetes + [envbuilder](https://github.com/coder/envbuilder) devcontainer starter embedded in the server's own `coder` binary (so it matches the installed version), pushed with `namespace=<workspace namespace>` and `use_kubeconfig=false`. Workspaces build their `devcontainer.json` repo in a pod, without Docker. A re-run keeps the admin and does not push the template again; if the admin's password was changed in the UI the template step is skipped with a warning. Both steps are best effort: on failure the install still succeeds and you finish in the UI.

Coder's own `CODER_ACCESS_URL` and `CODER_WILDCARD_ACCESS_URL` are set from that same domain on purpose (this step has no variable for them): Coder scopes its session cookie to the wildcard domain, so reaching the dashboard on a host outside it (or on another port) ends in a cookie error at login.

**Public or internal, never both** (the system config: `vps-access`, `SYSTEM_INTERNAL_APPS`): `public` (default) serves Coder on the server IP; `internal` serves `http://coder.<internal-ip>.nip.io` (and `*.<internal-ip>.nip.io` for workspace apps) on the same 80/443, behind the `internal-only` Traefik middleware (see `svc-k3s`): only clients of the internal network (Tailscale/Cloudflare) get through. Coder is a single route, so switching is a re-run with the other value.

**Public mode:** Traefik's 80/443 are the VPS's public ingress, so Coder is reachable from the internet like any ingress app (the step has no private port). Plain HTTP only unless you front it with TLS and terminate TLS in front of it; Let's Encrypt cannot issue a certificate for a nip.io name or a wildcard over HTTP-01.

The catalog's [`charts/coder`](../charts/coder/README.md) is the Rancher-UI route to the same upstream chart; do not install both.

## Workspace templates: use Kubernetes, not Docker

Coder runs as a pod on k3s (containerd), so there is no Docker daemon or `/var/run/docker.sock` for it. The **Docker** starter template fails at its first resource with `failed to create Docker client ... Cannot connect to the Docker daemon` (`docker_volume`). Create workspaces from a Kubernetes-based template instead: the step already creates `devcontainer`, or use Templates > Create > Starter templates > Kubernetes, which runs them as pods in the cluster, with these variables:

- `use_kubeconfig = false` (use the pod's own service account, not a kubeconfig);
- `namespace = coder` (the chart's service account may create pods and volume claims in its own namespace).

Do not mount a Docker socket into the Coder pod: there is no Docker on this node. A host with Docker (`vps-dokploy`) is the other route, and it is exclusive with k3s.

## Dev container platform: devcontainer-builder and a registry

Right after Coder is ready (before the admin and template steps, so it comes up even if those only warn), the step installs the [devcontainer-builder](https://deepspacecartel.github.io/devcontainer-builder/getting-started/platform/) chart, pointed at a BuildKit the step deploys itself (namespace `devcontainer-builder`, labelled Pod Security `privileged`, which BuildKit requires; chart 0.5.0, the latest published, cannot deploy its bundled BuildKit: its container name is the invalid Helm alias `buildkitBundled`, so `buildkit.deploy.enabled` is not used) and the `devcontainer-images` pull secret in the `coder` namespace.

**Template patch.** The `devcontainer` template is Coder's "Kubernetes (Devcontainer)" starter, patched when pushed: **VS Code Desktop** (`registry.coder.com/coder/vscode-desktop/coder`, folder `/workspaces`) is added first beside code-server and JetBrains (`helm/devcontainer-vscode.tf`), and the **CPU**, **Workspaces volume size** and **Repository** parameters get working icons (the starter's CPU emoji 404s and Repository has none). The pushed version is named `TEMPLATE_REV` in `run.sh` (`vps-r2`): an existing template with another version name gets a new version on the next run, so the patch reaches hosts that already have it. Registry modules are downloaded by Terraform when the template builds, so the Coder pod needs internet access.

**Registry.** By default an **in-cluster registry** (`registry:2`, 20Gi volume, anonymous, plain HTTP) is deployed in that namespace on host port 5000, reachable as `<node ip>:5000` by BuildKit (pods) and by containerd (which cannot resolve cluster DNS names). Port 5000 is declared `private` (`coder_registry`), so ufw and the FORWARD guard keep it off the internet. The builder maps `github.com` repos to `<node ip>:5000/devcontainers` and lists that host in `insecureRegistries`; if `/etc/rancher/k3s/registries.yaml` does not exist, the step creates it with an HTTP mirror for the registry and **restarts k3s once** (running pods keep running; an existing file is never edited, a warning says what to add). The final summary shows the registry address.

To use an **external registry** instead, set `CODER_DEVCONTAINER_REGISTRY_USER`, `CODER_DEVCONTAINER_REGISTRY_ORG` and `CODER_DEVCONTAINER_REGISTRY_TOKEN` (and optionally `CODER_DEVCONTAINER_REGISTRY`, default `ghcr.io`; the token needs to push and pull, GHCR `write:packages`); nothing in-cluster is deployed then.

**Chart version.** devcontainer-builder is third-party. With `CODER_DEVCONTAINER_BUILDER_VERSION` unset the latest chart is installed and its version is **logged** (`Pin it with CODER_DEVCONTAINER_BUILDER_VERSION=...`); set it to pin.

## Workspace namespace

One namespace, `CODER_WORKSPACE_NAMESPACE` (default `coder-workspaces`, the platform page's name), is used consistently: the step creates it, grants Coder's service account (`coder:coder`) a namespaced Role there (pods, PVCs, services, secrets, configmaps, events, deployments, replicasets), creates the `devcontainer-images` pull secret in it, and pushes the template with `namespace=<it>`. The Coder chart's own workspace permissions only cover the release namespace `coder`, which is why a template aimed at another namespace fails with `persistentvolumeclaims is forbidden`. A template that already exists with a different `namespace` gets a new version pushed. Set `CODER_WORKSPACE_NAMESPACE=coder` to run workspaces beside Coder instead. `down` leaves this namespace (and its workspaces' volumes) alone.

## Workspace templates

After the admin exists, one template is pushed (once; an existing one is left as is):

- **`kubernetes-devcontainer`** from devcontainer-builder's `templates/coder-kubernetes`, when the platform above is up **and** `CODER_DEVCONTAINER_BUILDER_REF` (a tag or commit of that repository) is set; the template is third-party code, so it is never taken from a default branch. It is pushed with `namespace=<workspace namespace>`, the in-cluster builder endpoint and the pull secret. Developers create a workspace from a git repository and branch.
- **`devcontainer` (Envbuilder starter)** otherwise, following [Add Envbuilder to a template](https://coder.com/docs/admin/integrations/devcontainers/envbuilder/add-envbuilder): the starter embedded in the server's own `coder` binary, with `namespace=<workspace namespace>` and `use_kubeconfig=false`.

```bash
sudo ZZ_SETUP_REF=<ref> CODER_DEVCONTAINER_BUILDER_REF=<tag> zz-setup tomgrv/vps -o app-coder
```

BuildKit's `buildkitd.toml` is set to push to the in-cluster registry over plain HTTP (`http = true`); an external registry needs nothing.

Private repositories need a Coder external auth provider with the ID `github` and the template pushed with `--var external_auth_id=github` (not done here). Subdomain apps rely on the wildcard access URL above. If a push warns, the warning names the step that failed; after fixing it, re-run the step (`sudo vps-setup --only-app-coder`; the admin and template parts are idempotent and use the saved credentials), or run `coder templates push` by hand.

## Not verified on a live host

- The devcontainer-builder chart's value names (`buildkit.deploy.enabled`, `registryAuth`, `registryMapping`) and the `coder-kubernetes` template's variable names, both taken from its setup page and not read at source; the token's push/pull scope.
- The admin and template bootstrap: the `/users/first` and `/users/login` API shapes, the `kubernetes-devcontainer` id, the `use_kubeconfig`/`namespace` variable names, and whether the template needs more (such as a cache repository).
- The guide's `bitnamilegacy/postgresql` image override needs `global.security.allowInsecureImages=true` on recent Bitnami charts (set here).
- The chart's `ingress.enable`/`className`/`host`/`wildcardHost` value names.
- That the login cookie error was fully explained by the host/wildcard mismatch: inferred from Coder's wildcard docs, not reproduced.

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `ZZ_SECRETS_FILE` | no | `/root/.vps-secrets.env` | Owner-only env file holding the credentials the steps generate |
| `CODER_ADMIN_EMAIL` | no | `admin@<wildcard domain>` | Email of the first Coder admin |
| `CODER_ADMIN_PASSWORD` | no | _(generated)_ | Password of the first Coder admin |
| `CODER_ADMIN_USERNAME` | no | `admin` | Username of the first Coder admin |
| `CODER_WORKSPACE_NAMESPACE` | no | `coder-workspaces` | Namespace workspaces run in (see below) |
| `CODER_CHART_VERSION` | no | _(latest)_ | Pin the Coder chart version (e.g. `2.37.4` stable) |
| `CODER_DEVCONTAINER_BUILDER_REF` | no | _(unset)_ | Pinned tag/commit of devcontainer-builder's Coder template (required to push that template; else the Envbuilder starter) |
| `CODER_DEVCONTAINER_BUILDER_VERSION` | no | _(latest, logged)_ | devcontainer-builder chart version |
| `CODER_DEVCONTAINER_REGISTRY` | no | `ghcr.io` | External registry host (used with the user, org and token) |
| `CODER_DEVCONTAINER_REGISTRY_ORG` | no | _(unset)_ | External registry org/user images are pushed under |
| `CODER_DEVCONTAINER_REGISTRY_TOKEN` | no | _(unset)_ | External registry token able to push and pull; with user and org it replaces the in-cluster registry |
| `CODER_DEVCONTAINER_REGISTRY_USER` | no | _(unset)_ | Registry username for the token |
| `CODER_DB_PASSWORD` | no | _(generated)_ | PostgreSQL password for Coder |
| `CODER_DB_STORAGE` | no | `10Gi` | PostgreSQL volume size |

## Ports and access

| Port   | Access  | Override              | What |
| ------ | ------- | --------------------- | ---- |
| `5000` | private | `CODER_REGISTRY_PORT` |      |

`public` ports are open to everyone; `private` ones only on the internal interface (`vps-security`).

The route is **public** by default (`public` = the server IP on 80/443, `internal` = the internal network only); `vps-access` or `SYSTEM_INTERNAL_APPS` / `SYSTEM_PUBLIC_APPS` change it.

## Removing (`down`)

```bash
sudo vps-setup --down-app-coder
```

Deletes the `coder` namespace, **including the PostgreSQL volume: all Coder data is lost.** Also forgets the saved database and admin passwords (devcontainer-builder, the registry and its images are left in place, with `/etc/rancher/k3s/registries.yaml`).

## Dependencies

`app-rancher` (which brings `svc-k3s`).

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape and the `package.json` shape. The install needs a live cluster.
