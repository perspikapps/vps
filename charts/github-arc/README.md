<!-- @format -->

# github-arc

Thin umbrella chart around the two official
[actions-runner-controller](https://github.com/actions/actions-runner-controller)
charts - the controller (`gha-runner-scale-set-controller`) and a runner
scale set (`gha-runner-scale-set`) - published through this repo's Rancher
Marketplace catalog (see the root [README](../../README.md#rancher-marketplace)).
It adds no templates of its own - just two dependency pins and defaults
under `values.yaml`'s `gha-runner-scale-set-controller:`/
`gha-runner-scale-set:` keys.

Installing this chart lets self-hosted GitHub Actions runners be
dispatched straight onto the k3s cluster it's installed on.

## Required values

Fill these in before installing - the install will fail (or succeed
with the placeholders below, which you do not want) otherwise:

| Value                                                   | Purpose                                                                                                                                                                      |
| ------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `gha-runner-scale-set.githubConfigUrl`                  | Org or repo URL runners register against, e.g. `https://github.com/perspikapps` or `https://github.com/perspikapps/vps`                                                      |
| `gha-runner-scale-set.githubConfigSecret.github_app_id` | GitHub App ID                                                                                                                                                                |
| `...github_app_installation_id`                         | GitHub App installation ID                                                                                                                                                   |
| `...github_app_private_key`                             | The GitHub App's private key PEM's full contents (paste the whole file, not a path - there's no host filesystem to read a path from once this installs through Rancher's UI) |

You create the GitHub App yourself first, following
[the ARC quickstart](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/get-started)

- this chart only wires its credentials into the cluster, authenticated
  via a GitHub App (the method the docs recommend over a personal access
  token).

Also review `gha-runner-scale-set.runnerScaleSetName` (what workflows
target via `runs-on: [self-hosted, <this-name>]`) and
`minRunners`/`maxRunners` (autoscaling range, default `0`/`5`) - see
`values.yaml`'s comments.

## Installing from Rancher

1. Add this repo's catalog under **Apps & Marketplace → Repositories**
   if you haven't already (`https://perspikapps.github.io/vps/`).
2. **Apps & Marketplace → Charts**, pick **github-arc**, fill in the
   required values above, and install. Both Helm releases land in a
   single `github` namespace.
3. Check on it with `kubectl -n github get autoscalingrunnersets` and
   `kubectl -n github get pods`.

## What's not covered

Neither release binds a port `ufw`/Traefik needs to know about -
runners connect outbound to GitHub, nothing needs to be reachable from
outside the cluster. Uninstalling from Rancher's UI removes both Helm
releases but leaves the `github` namespace and the GitHub App secret in
place; remove those yourself (`kubectl delete namespace github`) if you
want a clean slate.
