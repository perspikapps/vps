<!-- @format -->

# Upgrading

How to ship, and consume, a **breaking change** in the scripts this repo's
cloud-init and workflows bootstrap, without breaking CI or the release. Written
from the v1.0.0 release (`tomgrv/scripts` v1: `zz_*` → `zz-*`,
`<verb>-json|yaml` → `json-<verb>|yaml-<verb>`). Rename tables:
[`tomgrv/scripts/UPGRADING.md`](https://github.com/tomgrv/scripts/blob/main/UPGRADING.md).

## Version map

| Repo               | Before | After  |
| ------------------ | ------ | ------ |
| `tomgrv/scripts`   | v0.34  | v1.0.0 |
| `tomgrv/actions`   | v2.46  | v3.0.0 |
| `perspikapps/vps`  | v0.3.0 | v1.0.0 |

## What depends on the scripts here

- `cloud-init/kairos-vps-setup.yaml` and the docs run
  `curl … tomgrv/scripts/main/setup.sh | sh`, which installs the `zz-*` core.
  Every command invoked afterwards must use the new names.
- `.github/workflows/*` use `tomgrv/actions/...@<major>`.
- `.github/workflows/release-main.yml` calls
  `tomgrv/actions/release-promote@<major>` with `scripts-ref: <scripts major>`.

## Order of operations

1. `tomgrv/scripts` merged and released, then `tomgrv/actions` released (new
   major). Until then CI here fails at `zz_use: not found`.
2. **This repo**: rename script calls in docs, cloud-init and scripts; pin
   `tomgrv/actions@v3`; merge when green.
3. **Update `release-main.yml` in the same change**:
   `release-promote@v3` and `scripts-ref: v1`. Do not leave the old pins
   (`@v2.22.0`, `v0.3.0`) — the old `release-promote` still bootstraps `scripts`
   `main` and fails at `zz_use: not found`; this is only visible in a dry run.
4. `release-main.yml` with `dry_run: true`, then `false`. Confirm the tags.

## Checklist

1. Rewrite names in README, cloud-init, scripts and skills (regular files only,
   not symlinks; skip `CHANGELOG.md` / `package-lock.json`). Do not rename the
   data names `.zz_dist`, `config.zz_dist`, `~/.cache/zz_scripts`, `ZZ_*`.
2. Grep for leftovers, including quoted and Markdown-escaped forms
   (`"zz_dist"`, `zz\_*`).
3. PR title scope must be one of `vps-cockpit`, `vps-common`,
   `vps-dockermanager`, `vps-k3s`, `vps-marketplace`, `vps-rancher`,
   `vps-security`, `vps-setup`, `vps-system`, `vps-tailscale`; header ≤ 100 chars.
   Squash-merge with `!` in the title and a `BREAKING CHANGE:` footer.
4. After a squash merge the remote branch may survive; before reusing its name
   check that its tree equals `develop`, then push with `--force-with-lease`.
5. Re-running a failed check reuses the original event payload (old PR title).
   Push, or mark the PR ready for review (this also starts checks that never
   ran on the draft).

## Upgrading a deployed host

```sh
curl -fsSL https://raw.githubusercontent.com/tomgrv/scripts/main/setup.sh | sh
zz-update          # was: zz_update — refreshes the local script cache
```

Replace any custom use of `zz_*`, `*-json` or `merge-yaml` with the new names
(`zz-*`, `json-*`, `yaml-merge`, or the `json` / `yaml` dispatchers). Old names
remain only as long as the previous scripts major is installed.

## Rollback

Pin `tomgrv/actions@v2`, `release-promote@v2.22.0` and `scripts-ref: v0.3.0`
together and use the previous scripts major on the host; never mix majors.
