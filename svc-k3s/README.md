<!-- @format -->

# svc-k3s

k3s / kubectl / helm install (includes Traefik configuration).

Part of [`vps`](https://github.com/tomgrv/vps) · order 4 · on by default · needs root, Ubuntu · [how steps work](../README.md#contributing).

## Usage

```bash
sudo vps-setup --only-svc-k3s      # just this step (it is on by default)
sudo vps-setup --skip-svc-k3s      # leave it out of a full run
sudo vps-setup --down-svc-k3s      # remove it
sudo zz-setup ./ -o svc-k3s         # without vps-setup, from a checkout
```

## Internal routes

Public and internal services share Traefik's 80/443. An internal route has the internal domain as its host and the `internal-only` middleware (`kube-system-internal-only@kubernetescrd`, an `ipAllowList` created by this step from `vps-network internal-range`), so only clients of the internal network get through; the server IP answers them with 403. `externalTrafficPolicy: Local` keeps the client address visible to Traefik, and `allowCrossNamespace` lets any namespace use the middleware. Needs Traefik v3 (`traefik.io/v1alpha1`, `ipAllowList`). After the internal network changes, re-run this step.

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `K3S_EXTRA_ARGS` | no | _(unset)_ | Extra flags passed to the k3s installer |
| `K3S_VERSION` | no | _(unset)_ | Pin a k3s version |
| `K3S_TRAEFIK_ACME_EMAIL` | no | `admin@example.com` | Contact email registered with Let's Encrypt |
| `K3S_TRAEFIK_ACME_STAGING` | no | `true` | Use Let's Encrypt's staging environment (true/false) |
| `K3S_TRAEFIK_DASHBOARD_PORT` | no | `8088` | Traefik dashboard port (private access only) |

## Ports and access

| Port   | Access  | Override                     | What                                                                       |
| ------ | ------- | ---------------------------- | -------------------------------------------------------------------------- |
| `80`   | public  | `K3S_HTTP_PORT`              | HTTP Traefik ingress, also required for the Lets Encrypt HTTP-01 challenge |
| `443`  | public  | `K3S_HTTPS_PORT`             | HTTPS Traefik ingress                                                      |
| `8088` | private | `K3S_TRAEFIK_DASHBOARD_PORT` |                                                                            |

`public` ports are open to everyone; `private` ones only on the internal interface (`vps-security`).

## Outputs

| Output | Description |
| --- | --- |
| `KUBECONFIG` | Path to the k3s kubeconfig (/etc/rancher/k3s/k3s.yaml) |

## Removing (`down`)

`down` removes k3s itself, via its own uninstaller - **takes Rancher and every app-* app down with it**, since they all run on this cluster.

```bash
sudo vps-setup --down-svc-k3s
```

## Dependencies

No other step is required.

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz-use` line, the `up`/`down` dispatch, and that nothing but `zz-colors` is sourced) plus the `package.json` `bin`/`engines`/`config` shape. The install itself needs a live root Ubuntu box, so it has no automated coverage - see the root README's [Tests](../README.md#contributing).
