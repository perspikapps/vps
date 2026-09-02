<!-- @format -->

# vps-common

Shared bash helpers sourced by every feature's `run.sh` (and by
`vps-summary/run.sh`): the `ok` helper and leveled logging through
[`tomgrv/scripts`](https://github.com/tomgrv/scripts)'s `zz_colors`/`zz_log`,
an `ERR` trap that prints the failing command/file/line, apt helpers
(`apt_install`, `apt_update_once`), `retry`, `command_exists`,
`net_port`/`net_access`/`all_network_ports` (reading each feature's own
`package.json` `vps.ports`), `dispatch_action` (the `up`/`down` plumbing
every feature's `run.sh` ends with), `helm_teardown`, `patch_service_port`,
and `ensure_cert_manager`.

Not an installable step itself — excluded from `dispatch.sh`'s feature
discovery. A caller sources it like any other repo script, via `zz_use`:

```sh
zz_use perspikapps/vps/vps-common
. vps-common
```

(`dispatch.sh` re-execs from a full checkout when running via
`curl | sudo sh`, so every feature's own `run.sh` can rely on `zz_use`
already being bootstrapped there too — but each `run.sh` still bootstraps
`zz_use` itself first, for when it's run standalone.)

## `package.json`

Like every folder in this repo, `vps-common/`'s `package.json` declares a
`"bin"` entry (`{"vps-common": "run.sh"}`) matching the folder name, and a
`"name"` of `"@tomgrv/vps-common"` — this repo's own npm scope plus the
folder's bare name (see the root README's
[One folder per feature](../README.md#one-folder-per-feature) for why
that differs from [`tomgrv/scripts`](https://github.com/tomgrv/scripts)'s
own unscoped convention) — what `zz_use perspikapps/vps/vps-common`
relies on. Its real npm `"dependencies"` is empty: `zz_colors`/`zz_log`
aren't npm-resolvable workspace members (they live in `tomgrv/scripts`, a
separate repo, fetched at runtime by `zz_use` — not by `npm install`) —
listing them there would break a plain `npm install`. They're documented
instead under a `"zzUse"` field (`{"tomgrv/scripts": ["zz_colors",
"zz_log"]}`), which `npm`/workspace tooling ignores.

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s pure logic (`net_port`, `net_access`,
`all_network_ports`, `feature_package_json`, `dispatch_action`) against a
small fixture tree, plus syntax and `package.json`'s `bin` field. The rest
of `run.sh` (apt helpers, cert-manager, Helm teardown) needs a live
root/Ubuntu/k3s environment this suite doesn't have — see the root
README's [Tests](../README.md#tests) section for the full picture.
