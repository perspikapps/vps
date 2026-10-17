<!-- @format -->

# vps-common

Shared bash helpers sourced by every feature's `run.sh` (and by
`vps-setup/run.sh`): the `ok` helper and leveled logging through
[`tomgrv/scripts`](https://github.com/tomgrv/scripts)'s `zz-colors`/`zz-log`,
an `ERR` trap that prints the failing command/file/line, apt helpers
(`apt_install`, `apt_update_once`), `retry`, `command_exists`,
`net_port`/`all_network_ports` (reading each feature's own
`package.json` `config.ports`; an environment variable named after the port,
e.g. `COCKPIT_HTTP_PORT`, overrides it), `feature_dirs`/`ordered_feature_dirs`,
`download_run` (fetch and run an installer script via a private temp file),
`summary_host`, `vps_secret`/`vps_secret_set`/`vps_secret_unset` (credentials as
KEY=VALUE lines in the owner-only `/root/.vps-secrets.env`, written with
`zz-persist -s`; a legacy one-value file is read once and migrated),
`apt_purge`, `cockpit_refresh`, `dispatch_action` (the `up`/`down`/`summary` plumbing
every feature's `run.sh` ends with; `up`/`down` require root, `summary` is the
step's optional block of the final connection summary), `helm_teardown`, `patch_service_port`,
and `ensure_cert_manager`.

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
