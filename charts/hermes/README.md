<!-- @format -->

# hermes

Deploys [Hermes Agent](https://github.com/NousResearch/hermes-agent) - a
self-improving AI agent harness (learning loop, autonomous skill
creation, scheduled automation, multi-platform chat integrations) -
published through this repo's Rancher Marketplace catalog (see the root
[README](../../README.md#rancher-marketplace)).

Unlike [`argocd`](../argocd) and [`epinio`](../epinio), this is **not**
an umbrella chart around an upstream Helm chart - Hermes Agent ships
none. It's a from-scratch `Deployment`/`Service`/`Ingress`/`PVC` wrapping
a Docker image you build and push yourself from upstream's Dockerfile.

## Required values

Fill these in before installing:

| Value                           | Purpose                                                                                                                                                                                                                                      |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `image.repository`, `image.tag` | No official image is published. Build one from upstream and push it somewhere this cluster can pull from (see below).                                                                                                                        |
| `envFromSecretName`             | Name of a `Secret` (create it yourself, e.g. via `kubectl create secret generic`) holding LLM provider keys (e.g. `OPENROUTER_API_KEY`) and any messaging-platform tokens. See upstream's environment-variables reference for the full list. |

## Building and pushing the image

```bash
git clone https://github.com/NousResearch/hermes-agent
docker build -t <your-registry>/hermes-agent:<tag> hermes-agent/
docker push <your-registry>/hermes-agent:<tag>
```

## Installing from Rancher

1. Add this repo's catalog under **Apps & Marketplace → Repositories**
   if you haven't already (`https://perspikapps.github.io/vps/`).
2. Create the credentials `Secret` referenced by `envFromSecretName`
   above, in the same namespace you're about to install into.
3. **Apps & Marketplace → Charts**, pick **hermes**, fill in
   `image.repository`/`image.tag` and `envFromSecretName`, and install.
4. Set `dashboard.ingress.enabled: true` (plus `dashboard.ingress.host`
   and `dashboard.ingress.tlsIssuer`) to expose the dashboard through an
   Ingress instead of port-forwarding to the Service.

This chart runs Hermes's `gateway` and `dashboard` processes as two
containers in one pod (upstream's `docker-compose.yml` runs them as
separate host-networked containers sharing a volume - here they share
the pod's `~/.hermes` equivalent via a `PersistentVolumeClaim` mounted at
`/opt/data` instead). Set `apiServer.enabled: true` to also expose the
gateway's optional OpenAI-compatible API.
