<!-- @format -->

# cognee

Self-contained chart for [cognee](https://github.com/topoteretes/cognee) -
an AI memory engine that builds a semantic/graph knowledge layer for LLM
apps - published through this repo's Rancher Marketplace catalog (see the
root [README](../../README.md#rancher-marketplace)).

Unlike [`charts/argocd`](../argocd) and [`charts/epinio`](../epinio),
this is not a thin dependency wrapper: cognee has no official upstream
Helm chart, only a documented
[Docker Compose deploy](https://github.com/topoteretes/cognee#deploy-cognee).
This chart's templates run that same single-container "minimal" setup
(the `cognee/cognee:main` prebuilt image, single-user mode) as a
Deployment/Service/PVC instead - see
[the upstream minimal Docker Compose guide](https://github.com/topoteretes/cognee/blob/main/docs/minimal-docker-compose.md)
for what it mirrors.

## Required values

| Value       | Purpose                                                                                         |
| ----------- | ----------------------------------------------------------------------------------------------- |
| `llmApiKey` | LLM provider API key (OpenAI by default). The container fails to start without it - no default. |

## Installing from Rancher

1. Add this repo's catalog under **Apps & Marketplace → Repositories**
   if you haven't already (`https://perspikapps.github.io/vps/`).
2. **Apps & Marketplace → Charts**, pick **cognee**, fill in `llmApiKey`,
   and install. Cognee's API comes up on the Service's port `8000`
   (`ClusterIP` by default - enable `ingress.enabled` for a routable
   hostname, or `service.type: LoadBalancer`/`NodePort` instead).

## Notes

- `persistence.enabled` (on by default) keeps cognee's system/data
  directories on a PVC across pod restarts - disable it for a
  throwaway demo.
- This wraps the _minimal_ single-container demo only - it does not
  include cognee's optional UI, MCP server, or external
  Postgres/Neo4j/Redis profiles from the full source-based
  `docker-compose.yml`. Use `extraEnv` to point at an external
  `DB_PROVIDER`/vector store if you need more than the built-in
  SQLite/LanceDB defaults - see cognee's
  [`.env.template`](https://github.com/topoteretes/cognee/blob/main/.env.template)
  for the full list of supported variables.
- For production-grade deployments beyond this demo (auth, external
  storage backends, scaling), see cognee's own
  [deployment templates](https://github.com/topoteretes/cognee/blob/main/distributed/deploy/README.md)
  or [Cognee Cloud](https://docs.cognee.ai/cognee-cloud/overview).
