<!-- @format -->

# common

Shared bash helpers sourced by every feature's `run.sh` (and by
`summary/run.sh`): leveled logging (`log`/`ok`/`warn`/`die`, delegating to
[`tomgrv/scripts`](https://github.com/tomgrv/scripts)'s `zz_colors`/`zz_log`),
an `ERR` trap that prints the failing command/file/line, apt helpers
(`apt_install`, `apt_update_once`), `retry`, `command_exists`,
`net_port`/`net_access`/`all_network_ports` (reading each feature's own
`package.json` `vps.ports`), `dispatch_action` (the `up`/`down` plumbing
every feature's `run.sh` ends with), `helm_teardown`, `patch_service_port`,
and `ensure_cert_manager`.

Not an installable step itself — excluded from `dispatch.sh`'s feature
discovery. A caller sources it like any other repo script, via `zz_use`:

```sh
zz_use perspikapps/vps/common
. common
```

(`dispatch.sh` re-execs from a full checkout when running via
`curl | sudo sh`, so every feature's own `run.sh` can rely on `zz_use`
already being bootstrapped there too — but each `run.sh` still bootstraps
`zz_use` itself first, for when it's run standalone.)
