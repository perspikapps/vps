<!-- @format -->

# vps-cloudflare

Cloudflare Tunnel (`cloudflared`) plus WARP private network routes, as the VPS's private network.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `vps-setup`'s install sequence (order and default: `config` in its `package.json`). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

**Opt-in** (`config.default: false`), and an **alternative to `vps-tailscale`**, not an addition: both provide the private network that `access: "private"` ports (Cockpit, Rancher, the Traefik dashboard, the k3s API) are reachable on. `config.conflicts` (declared on both sides) makes `zz-setup` abort before any step starts when both are selected, and `up` itself refuses to run while Tailscale is up or persisted as the private interface (a host set up by an earlier run): run `sudo vps-setup --down-vps-tailscale` first, mind your SSH path.

## Usage

```bash
sudo CLOUDFLARE_TUNNEL_TOKEN=eyJ... vps-setup --skip-vps-tailscale --with-vps-cloudflare
```

Or directly, from a checkout (`up` is the default action):

```bash
sudo bash vps-cloudflare/run.sh up
sudo bash vps-cloudflare/run.sh down
```

## What it does

1. Installs `cloudflared` from Cloudflare's apt repo.
2. Creates `vps-cloudflare-private.service`: a dummy interface `vpscf0` holding `CLOUDFLARE_PRIVATE_IP`/32.
3. Creates `cloudflared.service` running the remotely-managed tunnel; the token is kept in `/etc/cloudflared/tunnel.env` (owner-only), not on the unit's command line.
4. Persists `VPS_PRIVATE_INTERFACE=vpscf0` (see [Private access](../README.md#private-access)); this step runs before `vps-security` for that reason.

## Cloudflare side (manual, once)

In Zero Trust: add a **private network route** `<CLOUDFLARE_PRIVATE_IP>/32` to the tunnel, enroll your devices with the WARP client, and make sure that range is not in WARP's split-tunnel _Exclude_ list (the default excludes the RFC 1918 ranges, which includes the default `10.254.254.1`). Then browse `https://<CLOUDFLARE_PRIVATE_IP>:9080` (Cockpit), etc.

## SSH

SSH needs no extra step here: the private route to `CLOUDFLARE_PRIVATE_IP` already carries port 22 for WARP clients (`ssh user@<CLOUDFLARE_PRIVATE_IP>`). Unlike Tailscale's `--ssh`, this step does not replace sshd's authentication, and it does not close the public SSH port - that stays `vps-security`'s decision (`SSH_PORT`).

## Verifying that private ports stay closed

From **another machine** (never the VPS itself: a connection to its own public address is delivered locally and proves nothing):

```bash
bash vps-cloudflare/run.sh verify <public-ip>
```

Fails if any `access: "private"` port answers on the public address.

## Removing (`down`)

Stops and removes both units and the token file, and forgets the private interface. Leaves the `cloudflared` package installed unless `PURGE_CLOUDFLARED=true`.

```bash
sudo vps-setup --down-vps-cloudflare
```

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `CLOUDFLARE_PRIVATE_IP` | no | `10.254.254.1` | Address WARP clients use to reach this VPS through the tunnel (a /32 on a dummy interface) |
| `CLOUDFLARE_TUNNEL_TOKEN` | yes | _(unset)_ | Cloudflare Tunnel token (Zero Trust > Networks > Tunnels) |
| `PURGE_CLOUDFLARED` | no | `false` | Also remove the cloudflared package on down (true/false) |

## Dependencies

`vps-common` (shared helpers) only; conflicts with `vps-tailscale` (see above).

## Not verified on a live host

Traffic from `cloudflared` to `CLOUDFLARE_PRIVATE_IP` is host-local, so it arrives on `lo` and the per-interface ufw rules for `vpscf0` are not what admits it; the public side stays closed because ufw and `vps-security`'s FORWARD guard still drop everything from the internet. Check that ports published by k3s (ServiceLB) or Docker answer on `CLOUDFLARE_PRIVATE_IP` through the tunnel, and that `curl -m 5 http://<public-ip>:<private-port>` still times out.

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape, the mutual-exclusion declaration and the token handling. The install itself needs a live root Ubuntu box and a tunnel, so it has no automated coverage - see the root README's [Tests](../README.md#tests).
