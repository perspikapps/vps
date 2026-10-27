<!-- @format -->

# vps-access

Confirms which services are **public** or **internal**, and the DNS domains they are reached on.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - one step in `vps-setup`'s install sequence (order and default: `config` in its `package.json`). See the root README's [One folder per feature](../README.md#one-folder-per-feature) for the full convention this folder follows.

## Usage

Runs as one step of a full `vps-setup` install/removal, or on its own through `zz-setup`, from a checkout:

```bash
sudo vps-setup --only-vps-access
```

Or from a checkout, without `vps-setup` (`up` by default; `zz-setup` runs the step's `run.sh`):

```bash
sudo zz-setup ./ -o vps-access
sudo zz-setup ./ -d vps-access
```

It runs after the internal network (`vps-tailscale`/`vps-cloudflare`) and before `vps-k3s`, so the steps that expose something (`app-rancher`, `app-coder`) read its answers.

## Visibility

A service that exposes a route declares its default in `config.visibility` of its `package.json` (`public` or `internal`). A service is **public** (server IP, Traefik 80/443) or **internal** (a host on the internal domain, same Traefik 80/443, behind the `internal-only` middleware: only clients of the internal network get through), never both; the private (local) ports are unaffected.

On a terminal, a menu lists every such service: a number cycles it between `public` and `internal`, Enter confirms. An `internal` choice without a internal address is kept `public` with a warning. Answers are saved to `/etc/vps-access.env`; the environment (`RANCHER_ACCESS`, `CODER_ACCESS`, ...) still wins.

## DNS

Two prompts confirm the domains, each with a fallback:

| Domain   | Set with                                | Fallback                 |
| -------- | --------------------------------------- | ------------------------ |
| external | `ACCESS_EXTERNAL_DOMAIN` (`vps-system`)        | `<public-ip>.nip.io`     |
| internal | `ACCESS_INTERNAL_DOMAIN`                       | `<internal-ip>.nip.io`    |

An empty answer uses the fallback. A domain whose `*.<domain>` does not resolve to the expected address is flagged, and the menu offers to keep it or use the fallback. The step then prints the host each service will be reached on.

Without a terminal (or with `ACCESS_MENU=false`) nothing is asked: saved or default choices are kept, and the same checks are only logged.

## Summary

Every step summary has the same paragraph (`vps-network summary-block`): a `Public:`, `Internal:` and `Local:` line with the URLs and what to know for each, then notes (credentials, DNS). Public is the server IP on 80/443, internal is the same 80/443 for internal-network clients only, local is the private ports (closed to the internet). The `vps-access` one lists which services are in which scope and the DNS state:

```text
 Access (each service is public OR internal, never both):
   Public:    coder (coder.apps.example.com) - HTTP/HTTPS 80/443 on 203.0.113.7, from the internet
   Internal:  rancher (rancher.100-64-0-1.nip.io) - HTTP/HTTPS 80/443 on 100.64.0.1, clients of the internal network only (source range 100.64.0.0/10)
   Local:     private ports, closed to the internet, on the VPS and its internal address: cockpit_http 9080, ...
   External domain: *.apps.example.com - custom, resolves to 203.0.113.7
   Internal domain: *.100-64-0-1.nip.io - fallback (nip.io), resolves to 100.64.0.1
```

## Removing (`down`)

`down` forgets the saved choices (each service goes back to its `config.visibility` default).

```bash
sudo vps-setup --down-vps-access
```

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `ACCESS_EXTERNAL_DOMAIN` | no | _(unset)_ | Wildcard DNS domain pointing at this VPS (e.g. `apps.example.com` for `*.apps.example.com`); empty = `<public-ip>.nip.io` fallback. Validated and saved by this step |
| `ACCESS_INTERNAL_DOMAIN` | no | _(unset)_ | Domain pointing at the internal address, for internal services; empty = `<internal-ip>.nip.io` |
| `ACCESS_MENU` | no | `true` | `false` skips the menus and keeps the saved or default choices |

## Dependencies

No other step is required.

## Tests

```bash
bats test.bats
```
