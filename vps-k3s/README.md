<!-- @format -->

# vps-k3s

k3s / kubectl / helm install (includes Traefik configuration).

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `dispatch.sh`'s install sequence (order `4`, enabled by default). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

Runs as one step of a full `dispatch.sh` install/removal, or standalone once `vps-common/run.sh` is reachable (see the root README's [Layout](../README.md#layout)):

```bash
sudo sh dispatch.sh --only-vps-k3s
```

Or directly, from a checkout (`up` is the default action):

```bash
sudo bash vps-k3s/run.sh up
sudo bash vps-k3s/run.sh down
```

## Removing (`down`)

`down` removes k3s itself, via its own uninstaller - **takes Rancher and anything installed via the Marketplace down with it**, since they all run on this cluster.

```bash
sudo sh dispatch.sh --down-vps-k3s
```

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `K3S_EXTRA_ARGS` | no | _(unset)_ | Extra flags passed to the k3s installer |
| `K3S_VERSION` | no | _(unset)_ | Pin a k3s version |
| `TRAEFIK_ACME_EMAIL` | no | `admin@example.com` | Contact email registered with Let's Encrypt |
| `TRAEFIK_ACME_STAGING` | no | `true` | Use Let's Encrypt's staging environment (true/false) |
| `TRAEFIK_DASHBOARD_PORT` | no | `8088` | Traefik dashboard port (Tailscale-only) |

## Outputs

| Output | Description |
| --- | --- |
| `KUBECONFIG` | Path to the k3s kubeconfig (/etc/rancher/k3s/k3s.yaml) |

## Dependencies

`vps-common` (shared helpers). `dispatch.sh` auto-enables these when this step is enabled - see the root README's [Dependencies between steps](../README.md#dependencies-between-steps).

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz_use`/`vps-common` wiring, `up()`/`down()`, and `dispatch_action`) plus `package.json`'s `bin`/`vps` fields. The step itself (a live apt/Helm/k3s install) needs a real root Ubuntu box to actually run - see the root README's [Tests](../README.md#tests) section for the full picture.
