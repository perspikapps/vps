<!-- @format -->

# svc-tailscale

Tailscale install.

Part of [`vps`](https://github.com/perspikapps/vps) · order 1 · on by default · needs root, Ubuntu · cannot run with `svc-cloudflare` · [how steps work](../README.md#contributing).

## Usage

```bash
sudo vps-setup --only-svc-tailscale      # just this step (it is on by default)
sudo vps-setup --skip-svc-tailscale      # leave it out of a full run
sudo vps-setup --down-svc-tailscale      # remove it
sudo zz-setup ./ -o svc-tailscale         # without vps-setup, from a checkout
```

## Internal access

On install this step persists `SYSTEM_INTERNAL_INTERFACE=tailscale0` to
`/etc/vps-network.env` (removed again on `down`). `vps-security` and the
final summary read it, so they never mention Tailscale themselves; it is also why
this step runs before `vps-security`. See the root README's
[Internal access](../README.md#what-is-reachable).

`svc-tailscale` and [`svc-cloudflare`](../svc-cloudflare/README.md) are **mutually exclusive** (`config.conflicts` on both sides): pick one internal network per VPS.

## Why `svc-tailscale`, not `tailscale`

This folder's `run.sh` calls the real `tailscale` CLI internally, so a
folder named plain `tailscale/` would make `zz-use perspikapps/vps/tailscale`
install this feature's own script as `tailscale`, shadowing the actual
binary it depends on (`zz-use` always installs `<name>/run.sh` under the
literal folder name requested - it has no notion of `package.json`'s
`"bin"` field at all). Prefixing every folder in this repo with `vps-`
(see the root README's [Contributing](../README.md#contributing))
sidesteps this collision uniformly instead of treating it as a special
case for this one feature.

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `TAILSCALE_AUTHKEY` | yes | _(unset)_ | Auth key to auto-join a tailnet |
| `TAILSCALE_EXTRA_ARGS` | no | _(unset)_ | Extra flags appended to tailscale up |

## Removing (`down`)

`down` logs out of the tailnet and disables `tailscaled`. Removes the `tailscale` package too.

```bash
sudo vps-setup --down-svc-tailscale
```

## Dependencies

No other step is required.

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz-use` line, the `up`/`down` dispatch, and that nothing but `zz-colors` is sourced) plus the `package.json` `bin`/`engines`/`config` shape. The install itself needs a live root Ubuntu box, so it has no automated coverage - see the root README's [Tests](../README.md#contributing).
