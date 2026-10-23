<!-- @format -->

# vps-common

Shared POSIX sh helpers sourced by every feature's `run.sh`: leveled logging
through [`tomgrv/scripts`](https://github.com/tomgrv/scripts)'s `zz-colors`/`zz-log`,
`command_exists`, `net_port`/`all_network_ports` (each feature's own
`package.json` `config.ports`; an environment variable named after the port, e.g.
`COCKPIT_HTTP_PORT`, overrides it), `feature_dirs` (the steps, through
`zz-workspaces`), the private-network and address helpers (`private_interface`,
`private_address`, `summary_host`, `public_ip`, `wildcard_domain`) and
`reapply_private_guard`.

Steps call the `zz-*` scripts directly, with no wrapper here: `zz-install -m`/`-r` for
system packages, `zz-install -u <url> -x <shell> <name>` to fetch and run an installer
script (curl retries), `zz-persist -f "$VPS_SECRETS_FILE"` (`-s -g 24` to create a
credential, `-r` to read, `-u` to remove) for credentials kept as KEY=VALUE lines in the
owner-only `/root/.vps-secrets.env`, `zz-persist -l -f <file> <line>` to ensure a line,
`zz-log s` for success lines, `yaml-render` for chart values, `kube-progress` /
`kube-diagnose` / `kube-teardown` / `kube-service-port` / `kube-cert-manager` for
Kubernetes, and `. zz-step` to end a step (it runs `up`/`down`/`summary` after checking
the step's `config.requires`: root, Ubuntu). A failing step is reported by `zz-setup`
itself (script and exit status).

Not an installable step itself — excluded from `vps-setup`'s feature
discovery. A caller sources it like any other repo script, via `zz-use`:

```sh
zz-use perspikapps/vps/vps-common
. vps-common
```

## `package.json`

Like every folder here: `"name": "@tomgrv/vps-common"` and a `"bin"` entry
(`{"vps-common": "run.sh"}`), which `zz-use perspikapps/vps/vps-common` relies
on (see the root README's
[One folder per feature](../README.md#one-folder-per-feature)). It has no
`engines.zz-setup`, so `zz-setup` never proposes it as a step. Its npm
`"dependencies"` is empty: `zz-colors`/`zz-log` live in `tomgrv/scripts` and are
fetched at runtime by `zz-use`, so listing them would break `npm install`; they
are documented under a `"zzUse"` field that npm ignores.

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s pure logic (`net_port`,
`all_network_ports`, `ordered_feature_dirs`, `feature_package_json`,
`dispatch_action`, `download_run`) against a
small fixture tree, plus syntax and `package.json`'s `bin` field. The rest
of `run.sh` (apt helpers, cert-manager, Helm teardown) needs a live
root/Ubuntu/k3s environment this suite doesn't have — see the root
README's [Tests](../README.md#tests) section for the full picture.
