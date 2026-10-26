<!-- @format -->

# vps-network

The network facts and state of this VPS, in one place. A **script, not a step**:
its `package.json` has a `bin` but no `engines.zz-setup`, so `zz-setup` never lists it.
`zz-setup` installs it on `PATH` with the steps, so they call `vps-network <command>` and never source it.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps).

## Usage

```sh
vps-network <command> [args...]
```

| Command                         | Prints / does                                                                     |
| ------------------------------- | --------------------------------------------------------------------------------- |
| `public-ip`                     | public IPv4: the default-route source address, or - behind NAT - what an echo service sees |
| `internal-interface`             | the interface carrying the internal network (private-port services) (`VPS_INTERNAL_INTERFACE`, else the persisted one) |
| `internal-address`               | its first IPv4 address (empty until it has one)                                   |
| `summary-host`                  | that address, else `<internal-ip>`, for the steps' summaries                       |
| `external-domain`               | `EXTERNAL_DOMAIN`, else the persisted one, else `<public-ip>.nip.io` (public address, never the internal one) |
| `access-domain public\|internal` | `external-domain`, or `<internal-ip>.nip.io` (dashes) for internal access; fails without a internal address |
| `internal-domain` | `INTERNAL_DOMAIN`, else the saved one, else `<internal-ip>.nip.io` |
| `visibility <service>` | `public` or `internal`: `<NAME>_ACCESS`, else the saved choice, else `config.visibility` of `vps-<service>`, else `public` |
| `visibilities` | every service declaring `config.visibility`, as TSV: name, visibility |
| `set-visibility <service> public\|internal` | persist a choice to `/etc/vps-access.env` (`vps-access`) |
| `set-internal-domain <domain>` | persist the internal domain there (`vps-access`) |
| `unset-access` | forget every saved access choice |
| `summary-block <title> <public> <internal> <local> [note...]` | the paragraph every step summary prints: a `Public:`, `Internal:` and `Local:` line (empty or `-` reads `none`), then the notes |
| `port <name>`                   | a port by name: `<NAME>_PORT` from the environment, else what the steps declare in `config.ports` |
| `ports`                         | every step's ports as TSV: name, port, access, note (the same override applies)  |
| `set-internal-interface <iface>` | persist the internal interface to `/etc/vps-internal-access.env` (`vps-tailscale`, `vps-cloudflare`) |
| `unset-internal-interface <iface>` | forget it again, when it is still `<iface>`                                     |
| `set-external-domain <domain>`  | persist the external domain to `/etc/vps-external-domain.env` (`vps-system`)      |
| `reapply-guard`                 | restart `vps-private-ports-guard.service` so its FORWARD rule is ahead of k3s's and Docker's again (best effort) |

## Environment

`VPS_SETUP_ROOT` (the checkout holding the steps; default: this one),
`VPS_INTERNAL_ACCESS_FILE`, `VPS_EXTERNAL_DOMAIN_FILE`, `VPS_INTERNAL_INTERFACE`, `EXTERNAL_DOMAIN`.

## Tests

```sh
bats test.bats
```

Covers the commands against a small fixture tree (`bats test.bats`).

## Renamed

The private network is now the **internal network** and the wildcard domain the **external domain**. Commands: `internal-interface`, `internal-address`, `set-internal-interface`, `unset-internal-interface`, `external-domain`, `set-external-domain`. Variables: `VPS_INTERNAL_INTERFACE`, `VPS_INTERNAL_ACCESS_FILE`, `EXTERNAL_DOMAIN`, `VPS_EXTERNAL_DOMAIN_FILE`. State files: `/etc/vps-internal-access.env` and `/etc/vps-external-domain.env`. A host set up before the rename keeps the old `/etc/vps-private-access.env` and `/etc/vps-wildcard-domain.env`: re-run `vps-tailscale` (or `vps-cloudflare`) and `vps-system` to write the new ones. `access: "private"` on a port is unchanged.
