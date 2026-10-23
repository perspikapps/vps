<!-- @format -->

# vps-system

Base system update & essentials.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `vps-setup`'s install sequence (order and default: `config` in its `package.json`). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

Runs as one step of a full `vps-setup` install/removal, or on its own through `zz-setup`, from a checkout:

```bash
sudo vps-setup --only-vps-system
```

Or directly, from a checkout (`up` is the default action):

```bash
sudo sh vps-system/run.sh up
```

## Removing (`down`)

This step has no `down` action - it's a one-shot base package upgrade, nothing to undo. Running `up` again is always safe (idempotent).

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `WILDCARD_DOMAIN` | no | _(unset)_ | Wildcard DNS domain pointing at this VPS (e.g. `apps.example.com` for `*.apps.example.com`); unset = nip.io fallback |
| `TZ` | no | _(unset)_ | Timezone to set on the VPS (e.g. Europe/Paris) |

## Wildcard DNS

Apps that need per-app subdomains (e.g. Coder's workspace apps) read one wildcard domain through `vps-network wildcard-domain`. If `WILDCARD_DOMAIN` is set, this step validates it and persists it to `/etc/vps-wildcard-domain.env`. If not, apps fall back to [nip.io](https://nip.io) on the VPS's public address (never the Tailscale/private one): `<a-b-c-d>.nip.io` (dashes, e.g. `54-37-230-112.nip.io`) and `*.<a-b-c-d>.nip.io` resolve to that IP with no DNS to set up. nip.io is a third-party service: use your own domain for anything you depend on.

## Dependencies

No other step is required.

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and static shape (the `zz-use` line, the functions `zz-setup` calls, and that nothing but `zz-colors` is sourced) plus the `package.json` `bin`/`engines`/`config` shape. The install itself needs a live root Ubuntu box, so it has no automated coverage - see the root README's [Tests](../README.md#tests).
