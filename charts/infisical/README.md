<!-- @format -->

# infisical

Thin umbrella chart around the upstream
[`infisical-standalone`](https://github.com/Infisical/infisical/tree/main/helm-charts/infisical-standalone)
chart, published through this repo's Rancher Marketplace catalog (see
the root [README](../../README.md#rancher-marketplace)). It adds no
templates of its own - just a dependency pin and defaults under
`values.yaml`'s `infisical-standalone:` key.

## Required values

Fill these in before installing:

| Value                                     | Purpose                                                                                                    |
| ------------------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| `infisical-standalone.ingress.hostName`   | Externally-reachable hostname for the bundled Ingress.                                                     |
| `infisical-secrets` Secret (not templated) | Root credentials (`ENCRYPTION_KEY`, `AUTH_SECRET`, `SITE_URL`, ...) - see `values.yaml`'s comments for the `kubectl create secret` command. |

## Installing from Rancher

1. Add this repo's catalog under **Apps & Marketplace → Repositories**
   if you haven't already (`https://perspikapps.github.io/vps/`).
2. Create the `infisical-secrets` Secret in the target namespace (see
   `values.yaml`'s comments) - the install will fail without it.
3. **Apps & Marketplace → Charts**, pick **infisical**, set
   `infisical-standalone.ingress.hostName` under the required values
   above, and install.

## What's bundled

Unlike `argocd`/`coder`, this one is install-and-go: the upstream
`infisical-standalone` chart bundles its own Postgres, Redis, and an
nginx Ingress controller (under its own `infisical-nginx`
IngressClass, so it won't collide with a cluster-wide nginx install).
Swap in your own managed Postgres/Redis instead for a production
install - see `values.yaml`'s comments and
[Infisical's self-hosting docs](https://infisical.com/docs/self-hosting/overview).
