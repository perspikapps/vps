<!-- @format -->

# coder

Thin umbrella chart around the upstream
[`coder`](https://github.com/coder/coder) chart, published through this
repo's Rancher Marketplace catalog (see the root
[README](../../README.md#rancher-marketplace)). It adds no templates of
its own - just a dependency pin and defaults under `values.yaml`'s
`coder:` key.

## Installing from Rancher

1. Add this repo's catalog under **Apps & Marketplace → Repositories**
   if you haven't already (`https://perspikapps.github.io/vps/`).
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
  deployment. Uncomment and set it in `values.yaml` (or fill it in via
  Rancher's install UI), ideally paired with an Ingress + TLS in front
  of it rather than the default bare `LoadBalancer`.

See [Coder's own setup docs](https://coder.com/docs/admin/setup) for the
full picture (external auth, TLS termination, workspace provisioners,
etc.) - none of that is covered by this chart's defaults.
