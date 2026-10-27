<!-- @format -->

# vps-network

The network facts and state of this VPS, in one place. A **script, not a step**:
its `package.json` has a `bin` but no `engines.zz-setup`, so `zz-setup` never lists it.
`zz-setup` puts every workspace bin on `PATH` (a copy, which finds the steps through `ZZ_SETUP_ROOT`, or `VPS_SETUP_ROOT`), so the steps call `vps-network <command>` and never source it. Run by hand outside `zz-setup`, set `VPS_SETUP_ROOT` to the checkout.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps).

## Usage

```sh
vps-network <command> [args...]
```

| Command                         | Prints / does                                                                     |
| ------------------------------- | --------------------------------------------------------------------------------- |
| `public-ip`                     | the instance address: the source address of the default route |
| `internal-interface`             | the interface carrying the internal network (private-port services) (`SYSTEM_INTERNAL_INTERFACE`, else the persisted one) |
| `internal-address`               | its first IPv4 address (empty until it has one)                                   |
| `summary-host`                  | that address, else `<internal-ip>`, for the steps' summaries                       |
| `external-domain`               | `SYSTEM_EXTERNAL_DOMAIN`, else the persisted one, else `<public-ip>.nip.io` (public address, never the internal one) |
| `access-domain public\|internal` | `external-domain`, or `<internal-ip>.nip.io` (dashes) for internal access; fails without a internal address |
| `internal-domain` | `SYSTEM_INTERNAL_DOMAIN`, else the saved one, else the external domain |
| `internal-range` | source CIDRs of the internal network's clients: what the provider declared with `set-internal-interface <iface> <range>`, else the internal address and loopback (used by the `internal-only` Traefik middleware) |
| `access-route <service>` | shell to `eval`: `route_access`, `route_domain`, `route_middlewares` (the `internal-only` Traefik middleware for internal, else empty) and `route_certresolver` (`letsencrypt` for public, none for internal); logs and prints `exit 1` on a bad choice or no domain |
| `visibility <service>` | `public` or `internal`, from the system config only: `SYSTEM_INTERNAL_APPS` / `SYSTEM_PUBLIC_APPS` (comma lists), else the saved choice, else `config.visibility` of `vps-<service>`, else `public` |
| `visibilities` | every service declaring `config.visibility`, as TSV: name, visibility; under `zz-setup` only the ones this run brings up (`ZZ_SETUP_UP`) |
| `set-visibility <service> public\|internal` | persist a choice to `/etc/vps-network.env` (`vps-access`) |
| `set-internal-domain <domain>` | persist the internal domain there (`vps-access`) |
| `unset-access` | forget every saved access choice |
| `summary-block <title> <public> <internal> <local> [note...]` | the paragraph every step summary prints: a `Public:`, `Internal:` and `Local:` line (empty or `-` reads `none`), then the notes |
| `port <name>`                   | a port by name: `<NAME>_PORT` from the environment, else what the steps declare in `config.ports` |
| `ports`                         | every step's ports as TSV: name, port, access, note (the same override applies)  |
| `set-internal-interface <iface> [<range>]` | persist the internal interface, and the source CIDRs of its clients when given, to `/etc/vps-network.env` (`svc-tailscale`, `svc-cloudflare`) |
| `unset-internal-interface <iface>` | forget it again, when it is still `<iface>`                                     |
| `set-external-domain <domain>`  | persist the external domain to `/etc/vps-network.env` (`vps-system`)      |
| `reapply-guard`                 | restart `vps-private-ports-guard.service` so its FORWARD rule is ahead of k3s's and Docker's again (best effort) |

## Environment

`VPS_SETUP_ROOT` / `ZZ_SETUP_ROOT` (the checkout holding the steps; default: the one the script sits in),
`SYSTEM_NETWORK_FILE`, `SYSTEM_INTERNAL_INTERFACE`, `SYSTEM_EXTERNAL_DOMAIN`. The three files older versions wrote (`vps-internal-access.env`, `vps-external-domain.env`, `vps-access.env`) are folded into `/etc/vps-network.env` on the first run and removed.

## Tests

```sh
bats test.bats
```

Covers the commands against a small fixture tree (`bats test.bats`).

## Renamed

The private network is now the **internal network** and the wildcard domain the **external domain**. Commands: `internal-interface`, `internal-address`, `set-internal-interface`, `unset-internal-interface`, `external-domain`, `set-external-domain`. Variables: `SYSTEM_INTERNAL_INTERFACE`, `SYSTEM_INTERNAL_ACCESS_FILE`, `SYSTEM_EXTERNAL_DOMAIN`, `SYSTEM_EXTERNAL_DOMAIN_FILE`. State files: `/etc/vps-network.env` and `/etc/vps-network.env`. A host set up before the rename keeps the old `/etc/vps-private-access.env` and `/etc/vps-wildcard-domain.env`: re-run `svc-tailscale` (or `svc-cloudflare`) and `vps-system` to write the new ones. `access: "private"` on a port is unchanged.
