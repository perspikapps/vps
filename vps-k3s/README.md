<!-- @format -->

# vps-k3s

k3s / kubectl / helm install (includes Traefik configuration).

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `vps-setup`'s install sequence (order and default: `config` in its `package.json`). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

Runs as one step of a full `vps-setup` install/removal, or on its own through `zz-setup`, from a checkout:

```bash
sudo vps-setup --only-vps-k3s
```

Or directly, from a checkout (`up` is the default action):

```bash
sudo sh vps-k3s/run.sh up
sudo sh vps-k3s/run.sh down
```

## Removing (`down`)

`down` removes k3s itself, via its own uninstaller - **takes Rancher and every app-* app down with it**, since they all run on this cluster.

```bash
sudo vps-setup --down-vps-k3s
```

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `SYSTEM_K3S_EXTRA_ARGS` | no | _(unset)_ | Extra flags passed to the k3s installer |
| `SYSTEM_K3S_VERSION` | no | _(unset)_ | Pin a k3s version |
| `SYSTEM_INTERNAL_SOURCE_RANGE` | no | _(Tailscale `100.64.0.0/10`, else the internal address)_ | Source CIDRs (comma separated) of the internal network's clients, allowed on internal routes (the `internal-only` middleware) |
| `SYSTEM_TRAEFIK_ACME_EMAIL` | no | `admin@example.com` | Contact email registered with Let's Encrypt |
| `SYSTEM_TRAEFIK_ACME_STAGING` | no | `true` | Use Let's Encrypt's staging environment (true/false) |
| `SYSTEM_TRAEFIK_DASHBOARD_PORT` | no | `8088` | Traefik dashboard port (private access only) |

## Outputs

| Output | Description |
| --- | --- |
| `KUBECONFIG` | Path to the k3s kubeconfig (/etc/rancher/k3s/k3s.yaml) |

## Dependencies

No other step is required.

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz-use` line, the `up`/`down` dispatch, and that nothing but `zz-colors` is sourced) plus the `package.json` `bin`/`engines`/`config` shape. The install itself needs a live root Ubuntu box, so it has no automated coverage - see the root README's [Tests](../README.md#tests).

## Internal routes

Public and internal services share Traefik's 80/443. An internal route has the internal domain as its host and the `internal-only` middleware (`kube-system-internal-only@kubernetescrd`, an `ipAllowList` created by this step from `vps-network internal-range`), so only clients of the internal network get through; the server IP answers them with 403. `externalTrafficPolicy: Local` keeps the client address visible to Traefik, and `allowCrossNamespace` lets any namespace use the middleware. Needs Traefik v3 (`traefik.io/v1alpha1`, `ipAllowList`). After the internal network changes, re-run this step.
