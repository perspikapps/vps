<!-- @format -->

# vps-network

The network facts and state of this VPS, in one place. A **script, not a step**:
its `package.json` has a `bin` but no `engines.zz-setup`, so `zz-setup` never lists it.
The steps call it by path (`vps_network="$(dirname "$0")/../vps-network/run.sh"`), never source it.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps).

## Usage

```sh
vps-network <command> [args...]
```

| Command                         | Prints / does                                                                     |
| ------------------------------- | --------------------------------------------------------------------------------- |
| `public-ip`                     | public IPv4: the default-route source address, or - behind NAT - what an echo service sees |
| `private-interface`             | the interface carrying the private-only services (`VPS_PRIVATE_INTERFACE`, else the persisted one) |
| `private-address`               | its first IPv4 address (empty until it has one)                                   |
| `summary-host`                  | that address, else `<private-ip>`, for the steps' summaries                       |
| `wildcard-domain`               | `WILDCARD_DOMAIN`, else the persisted one, else `<public-ip>.nip.io` (public address, never the private one) |
| `port <name>`                   | a port by name: `<NAME>_PORT` from the environment, else what the steps declare in `config.ports` |
| `ports`                         | every step's ports as TSV: name, port, access, note (the same override applies)  |
| `set-private-interface <iface>` | persist the private interface to `/etc/vps-private-access.env` (`vps-tailscale`, `vps-cloudflare`) |
| `unset-private-interface <iface>` | forget it again, when it is still `<iface>`                                     |
| `set-wildcard-domain <domain>`  | persist the wildcard domain to `/etc/vps-wildcard-domain.env` (`vps-system`)      |
| `reapply-guard`                 | restart `vps-private-ports-guard.service` so its FORWARD rule is ahead of k3s's and Docker's again (best effort) |

## Environment

`VPS_SETUP_ROOT` (the checkout holding the steps; default: this one),
`VPS_PRIVATE_ACCESS_FILE`, `VPS_WILDCARD_FILE`, `VPS_PRIVATE_INTERFACE`, `WILDCARD_DOMAIN`.

## Tests

```sh
bats test.bats
```

Covers the commands against a small fixture tree (`bats test.bats`).
