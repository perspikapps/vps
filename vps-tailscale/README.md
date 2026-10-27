<!-- @format -->

# vps-tailscale

Tailscale install.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `vps-setup`'s install sequence (order and default: `config` in its `package.json`). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

Runs as one step of a full `vps-setup` install/removal, or on its own through `zz-setup`, from a checkout:

```bash
sudo vps-setup --only-vps-tailscale
```

Or from a checkout, without `vps-setup` (`up` by default; `zz-setup` runs the step's `run.sh`):

```bash
sudo zz-setup ./ -o vps-tailscale
sudo zz-setup ./ -d vps-tailscale
```

## Internal access

On install this step persists `SECURITY_INTERNAL_INTERFACE=tailscale0` to
`/etc/vps-internal-access.env` (removed again on `down`). `vps-security` and the
final summary read it, so they never mention Tailscale themselves; it is also why
this step runs before `vps-security`. See the root README's
[Internal access](../README.md#private-access).

`vps-tailscale` and [`vps-cloudflare`](../vps-cloudflare/README.md) are **mutually exclusive** (`config.conflicts` on both sides): pick one internal network per VPS.

## Removing (`down`)

`down` logs out of the tailnet and disables `tailscaled`. Leaves the `tailscale` package itself installed unless `TAILSCALE_PURGE=true`.

```bash
sudo vps-setup --down-vps-tailscale
```

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `TAILSCALE_PURGE` | no | `false` | Also remove the tailscale package on down (true/false) |
| `TAILSCALE_AUTHKEY` | yes | _(unset)_ | Auth key to auto-join a tailnet |
| `TAILSCALE_EXTRA_ARGS` | no | _(unset)_ | Extra flags appended to tailscale up |

## Dependencies

No other step is required.

## Why `vps-tailscale`, not `tailscale`

This folder's `run.sh` calls the real `tailscale` CLI internally, so a
folder named plain `tailscale/` would make `zz-use perspikapps/vps/tailscale`
install this feature's own script as `tailscale`, shadowing the actual
binary it depends on (`zz-use` always installs `<name>/run.sh` under the
literal folder name requested - it has no notion of `package.json`'s
`"bin"` field at all). Prefixing every folder in this repo with `vps-`
(see the root README's [One folder per feature](../README.md#one-folder-per-feature))
sidesteps this collision uniformly instead of treating it as a special
case for this one feature.

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz-use` line, the `up`/`down` dispatch, and that nothing but `zz-colors` is sourced) plus the `package.json` `bin`/`engines`/`config` shape. The install itself needs a live root Ubuntu box, so it has no automated coverage - see the root README's [Tests](../README.md#tests).
