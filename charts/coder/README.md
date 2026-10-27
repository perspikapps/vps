<!-- @format -->

# coder

Thin umbrella chart around the upstream
[`coder`](https://github.com/coder/coder) chart, published through this
repo's Rancher Marketplace catalog (see the root
[README](../../README.md#rancher-marketplace)). It adds one Ingress
template (served at `coder.<server domain>`, see
[Server domain](#server-domain)), a dependency pin and defaults under
`values.yaml`'s `coder.coder` key (the upstream chart's own root key is
also `coder`).

## Installing from Rancher

1. Add this repo's catalog under **Apps & Marketplace → Repositories**
   if you haven't already (`https://tomgrv.github.io/vps/`).
2. **Apps & Marketplace → Charts**, pick **coder**, review/edit the
   values (see `values.yaml`'s comments), and install.

## What's required

Unlike `argocd`/`epinio`, this one isn't install-and-go - Coder needs a
Postgres database to store its state:

- **`CODER_PG_CONNECTION_URL`**: a `postgresql://` connection URL for a
  database you've already provisioned (this chart does not bundle one).
  `values.yaml` wires it from a `coder-db-url` Secret's `url` key by
  default - create that Secret in the `coder` namespace before
  installing, or point `values.yaml` at your own Secret/inline value.
- **`CODER_ACCESS_URL`**: the externally-reachable URL for the
  deployment. Set it to `http://coder.<server domain>` (the Ingress this
  chart creates) in `values.yaml` or Rancher's install UI; unset, Coder
  opens a public tunnel.

## Server domain

The chart serves the app on `<app>.<domain>` through a Traefik Ingress
(`ClusterIP` Service, no LoadBalancer, so it never competes with Traefik
for ports 80/443). `<domain>` is `global.domain` if set, otherwise the
host of Rancher's own server URL (`global.cattle.url`, injected by
Rancher on install); when that host is a bare IP the domain becomes
`<ip>.nip.io`. Point a wildcard DNS record (`*.<domain>`) at the server
for a real FQDN. `ingress.host` overrides the generated host.

See [Coder's own setup docs](https://coder.com/docs/admin/setup) for the
full picture (external auth, TLS termination, workspace provisioners,
etc.) - none of that is covered by this chart's defaults.
