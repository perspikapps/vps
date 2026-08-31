<!-- @format -->

# epinio

Thin umbrella chart around the upstream
[`epinio`](https://github.com/epinio/helm-charts) chart, published
through this repo's Rancher Marketplace catalog (see the root
[README](../../README.md#rancher-marketplace)). It adds no templates
of its own - just a dependency pin and defaults under `values.yaml`'s
`epinio:` key.

## Required values

Fill these in before installing - the install will fail (or succeed
with the placeholders below, which you do not want) otherwise:

| Value                      | Purpose                                                                                                                                                     |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `epinio.global.domain`     | Wildcard DNS domain pointed at your cluster's ingress IP. Epinio creates `epinio.<domain>`, `auth.<domain>`, and one hostname per `epinio push`ed app.      |
| `epinio.api.adminPassword` | Admin login password. This repo's old bash install generated and saved a random one; the Rancher UI install has no such step, so set a real value yourself. |

Also review `epinio.global.tlsIssuer` and the three `ingressClassName`
values (`epinio.ingress`, `epinio.server`, `epinio.containerregistry`)

- see `values.yaml`'s comments.

## Installing from Rancher

1. Add this repo's catalog under **Apps & Marketplace → Repositories**
   if you haven't already (`https://perspikapps.github.io/vps/`).
2. Make sure cert-manager is installed on the cluster (Rancher/ArgoCD
   installs pull it in already; otherwise install it separately first
    - Epinio's Ingresses need a cert-manager Issuer to come up).
3. **Apps & Marketplace → Charts**, pick **epinio**, fill in
   `global.domain` and `api.adminPassword` under the required values
   above, and install.
4. Log in with the [epinio CLI](https://epinio.io):
   `epinio login -u admin -p '<password>' https://epinio.<domain>`,
   then deploy an app from a source directory with `epinio push`.

This chart also deploys SeaweedFS (S3-compatible storage for source
blobs), its own container registry, and Dex on top of Epinio itself -
more images to pull than most charts, so a slow first install is
normal.
