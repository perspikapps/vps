<!-- @format -->

# svc-cloudflare

Cloudflare Tunnel (`cloudflared`) plus WARP internal network routes, as the VPS's internal network.

**Opt-in** (`config.default: false`), and an **alternative to `svc-tailscale`**, not an addition: both provide the internal network that `access: "private"` ports (Cockpit, Rancher, the Traefik dashboard, the k3s API) are reachable on. `config.conflicts` (declared on both sides) makes `zz-setup` abort before any step starts when both are selected, and `up` itself refuses to run while Tailscale is up or persisted as the internal interface (a host set up by an earlier run): run `sudo vps-setup --down-svc-tailscale` first, mind your SSH path.

Part of [`vps`](https://github.com/tomgrv/vps) · order 1.5 · opt-in · needs root, Ubuntu · cannot run with `svc-tailscale` · [how steps work](../README.md#contributing).

## Usage

```bash
sudo vps-setup --with-svc-cloudflare      # add it to a full run
sudo vps-setup --only-svc-cloudflare      # just this step
sudo vps-setup --down-svc-cloudflare      # remove it
sudo zz-setup ./ -o svc-cloudflare         # without vps-setup, from a checkout
```

## What it does

1. Installs `cloudflared` from Cloudflare's release binary (any distribution).
2. Creates `svc-cloudflare-private.service`: a dummy interface `vpscf0` holding `CLOUDFLARE_INTERNAL_IP`/32.
3. Creates `cloudflared.service` running the remotely-managed tunnel; the token is kept in `/etc/cloudflared/tunnel.env` (owner-only), not on the unit's command line.
4. Persists `SYSTEM_INTERNAL_INTERFACE=vpscf0` (see [Internal access](../README.md#what-is-reachable)); this step runs before `vps-security` for that reason.

## Cloudflare side (manual, once)

In Zero Trust: add a **internal network route** `<CLOUDFLARE_INTERNAL_IP>/32` to the tunnel, enroll your devices with the WARP client, and make sure that range is not in WARP's split-tunnel _Exclude_ list (the default excludes the RFC 1918 ranges, which includes the default `10.254.254.1`). Then browse `https://<CLOUDFLARE_INTERNAL_IP>:9080` (Cockpit), etc.

## SSH

SSH needs no extra step here: the private route to `CLOUDFLARE_INTERNAL_IP` already carries port 22 for WARP clients (`ssh user@<CLOUDFLARE_INTERNAL_IP>`). Unlike Tailscale's `--ssh`, this step does not replace sshd's authentication, and it does not close the public SSH port - that stays `vps-security`'s decision (`SYSTEM_SSH_PORT`).

## Verifying that private ports stay closed

From **another machine** (never the VPS itself: a connection to its own public address is delivered locally and proves nothing):

```bash
vps-network verify <public-ip>
```

Fails if any `access: "private"` port answers on the public address.

## Not verified on a live host

Traffic from `cloudflared` to `CLOUDFLARE_INTERNAL_IP` is host-local, so it arrives on `lo` and the per-interface ufw rules for `vpscf0` are not what admits it; the public side stays closed because ufw and `vps-security`'s FORWARD guard still drop everything from the internet. Check that ports published by k3s (ServiceLB) or Docker answer on `CLOUDFLARE_INTERNAL_IP` through the tunnel, and that `curl -m 5 http://<public-ip>:<private-port>` still times out.

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `CLOUDFLARE_INTERNAL_IP` | no | `10.254.254.1` | Address WARP clients use to reach this VPS through the tunnel (a /32 on a dummy interface) |
| `CLOUDFLARE_TUNNEL_TOKEN` | yes | _(unset)_ | Cloudflare Tunnel token (Zero Trust > Networks > Tunnels) |
| `CLOUDFLARE_VERSION` | no | _(latest)_ | cloudflared release to install, e.g. `2025.1.0` |
| `CLOUDFLARE_SHA256` | no | _(not checked)_ | sha256 of that release's binary, or a JSON object keyed `<os>_<arch>` |

## Removing (`down`)

Stops and removes both units and the token file, and forgets the internal interface. Removes the `cloudflared` binary and its apt repo too.

```bash
sudo vps-setup --down-svc-cloudflare
```

## Dependencies

Conflicts with `svc-tailscale` (see above).

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape, the mutual-exclusion declaration and the token handling. The install itself needs a live root Ubuntu box and a tunnel, so it has no automated coverage - see the root README's [Tests](../README.md#contributing).
