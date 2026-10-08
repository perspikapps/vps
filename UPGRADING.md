<!-- @format -->

# Upgrading and breaking-change management

A reusable procedure for shipping, and consuming, a **breaking change** across
the repos that depend on each other (`tomgrv/scripts` → `tomgrv/actions` →
`tomgrv/devcontainer-features` → consumers such as `perspikapps/vps`). The same
generic core is kept in each repo's `UPGRADING.md`; only section 0 differs.

## 0. In this repo: `perspikapps/vps` (consumer)

- **Role:** consumer. Cloud-init and docs run
  `curl … tomgrv/scripts/main/setup.sh | sh`, which installs the provider's
  command set; workflows pin `tomgrv/actions@v<major>`.
- **What to update on every upstream breaking change:** command names in
  README/cloud-init/scripts, `tomgrv/actions@<major>` pins, and
  `.github/workflows/release-main.yml` (`release-promote@<major>` and
  `scripts-ref`) **in the same PR**. Leaving the old release pins fails only in
  a dry run: the old `release-promote` still bootstraps the provider's `main`.
- **Deployed hosts:** re-run the `setup.sh` one-liner, then `zz-update`.
- **PR title scope:** one of `vps-cockpit`, `vps-common`, `vps-dockermanager`,
  `vps-k3s`, `vps-marketplace`, `vps-rancher`, `vps-security`, `vps-setup`,
  `vps-system`, `vps-tailscale`.
- **Release:** `.github/workflows/release-main.yml` (`dry_run` first).

## 1. Principles

- **A breaking change promotes the major, everywhere it is visible.** Floating
  tags (`v1`, `v3`) only move inside a major, so anything pinned to the old major
  keeps resolving to the old code forever. That is a feature (rollback) and a
  trap (stale pins).
- **Providers ship before consumers.** Order work along the dependency chain;
  never the other way round.
- **Every consumer needs two things: the new name/behaviour and a new pin.**
  Changing one without the other is the usual cause of a broken upgrade.
- **Dry-run before every release**, and verify the resulting tags afterwards.
- **Write the breaking marker where the release tooling reads it:** `!` in the
  Conventional Commit title **and** a `BREAKING CHANGE:` footer in the squash
  commit.

## 2. Roles and the dependency chain

| Role                  | Owns                              | Typical repos here                     |
| --------------------- | --------------------------------- | -------------------------------------- |
| **Provider**          | The commands/APIs being changed   | `tomgrv/scripts`                       |
| **Tooling**           | Actions that install and run them | `tomgrv/actions`                       |
| **Distributor**       | Features/stubs copied to others   | `tomgrv/devcontainer-features`         |
| **Consumer**          | Calls everything above            | `perspikapps/vps`, any downstream repo |

Chain: **Provider → Tooling → Distributor → Consumer.** CI in every repo
installs the provider's `main` and runs the **published** tooling major, so a
change in the provider is visible to every repo's CI the moment it reaches
`main`.

## 3. Procedure

### 3.1 Plan

1. Write down the change as a table: old → new (names, flags, paths, config
   keys, tags). Decide what is **deliberately unchanged** (data formats, cache
   directories, environment variables) and say so in the table.
2. Inventory consumers: `grep` every repo for the old names **and** for the pins
   (`tomgrv/actions@v<old>`, `scripts-ref: v<old>`, pinned `release-promote`
   tags, workflow stubs deployed to other repos).
3. Compute the version map (old → new major) for every repo in the chain.
4. Decide compatibility: hard break (preferred when old and new cannot coexist)
   or a deprecation window with aliases. Record the decision in the PR.

### 3.2 Implement (per repo, provider first)

1. Rename files/folders with `git mv`; update manifests, workspace lists,
   `bin` entries, peer dependencies.
2. Rewrite references with a **word-bounded** pattern on **regular files only**.
   Skip `CHANGELOG.md`, lockfiles, symlinks, historical review documents.
3. Rewrite the **pins** in the same change: workflows, composite actions, docs,
   and **stubs that are deployed to other repos**.
4. **Merge the base branch again before finishing.** Work merged meanwhile still
   uses the old names and can break the merge tree.
5. Add a compatibility layer only if step 3.1.4 says so.

### 3.3 Verify

1. Run the suite with a **fresh cache** and a clean `PATH`; a stale local cache
   makes a correct install look broken.
2. Compare every failure with the pre-change commit (`git worktree add <dir> <base>`).
   Only failures that are new count; environmental ones (tool flavour, git
   identity) fail on the base too.
3. Re-grep for leftovers, including **quoted** forms (`"$BIN/old"`) and
   **escaped Markdown** (`old\_name`).
4. Read your own diff adversarially: what would make CI or a consumer reject it?

### 3.4 Ship

Follow the chain; for each repo:

1. Open the PR (title scope and ≤ 100-character header per repo rules).
2. Mark it **ready for review** only when you want the full check set; some
   checks never run on drafts.
3. Merge when green. If CI is red **only** because it runs the not-yet-released
   provider/tooling, that is the known deadlock: merge needs an explicit
   decision, and the release workflow must bootstrap from the checked-out code
   (e.g. `uses: ./<action>`) instead of the previous published tag.
4. Squash-merge when merge commits are disabled; carry the breaking marker.
5. `workflow_dispatch` the release with `dry_run: true`, read the result, then
   run it for real.
6. Verify the new tags (`v<major>`, `v<major>.<minor>`, `v<major>.<minor>.<patch>`).
7. Only then move on to the next repo in the chain.

### 3.5 Follow-up pins

After the new majors exist, bump every remaining `@v<old>` /
`scripts-ref: v<old>` (including the provider's and tooling's own workflows),
merge, and cut a patch release. Re-run the leftover grep on each repo's
released `develop`.

### 3.6 Communicate

Link this guide from the README/`CLAUDE.md`, put the old → new table and the
new pins in the release notes, and tell consumers the order in section 5.

## 4. Failure catalogue

| Symptom                                                      | Cause                                                                    | Fix                                                                  |
| ------------------------------------------------------------ | ------------------------------------------------------------------------ | -------------------------------------------------------------------- |
| `<old>: not found` in CI of every repo                       | CI runs the published tooling major that still calls the old name        | Release provider, then tooling; pin the new major                    |
| Release fails although the pin points at an old tag          | The pinned tooling bootstraps the provider's **`main`**, not its pin     | Move the release workflow to the new tooling major                   |
| `npm install` 404 on a renamed package                       | A file merged from the base still lists the old package name             | Merge the base again, rewrite the new files                          |
| `Syntax error: Bad function name` in a stub                  | POSIX `sh` function names cannot contain `-`                             | Make the stub an executable on `PATH`                                |
| A test still looks for the old name                          | Quoted or Markdown-escaped occurrences missed by the rewrite             | Grep for quotes and `\_` after rewriting                             |
| A symlinked file became a regular file                       | `sed -i` replaces symlinks                                               | Rewrite regular files only                                           |
| Check re-run still sees the old PR title                     | Re-runs reuse the original event payload                                 | Push a commit or mark the PR ready for review                        |
| `non-fast-forward` when reusing the PR branch name           | The remote branch survived the squash merge                              | Verify its tree equals the base, then `--force-with-lease=<ref>:<sha>` |
| Install fails only locally                                   | Stale cache from before the provider release                             | Use a fresh cache directory                                          |
| Title check fails on scope                                   | Each repo has its own scope enum                                         | Use a scope from the repo's list                                     |

## 5. Upgrading a consumer

```sh
# 1. find old names (adapt the pattern to the change table)
grep -rIl -E '<old-name-1>|<old-name-2>' . --exclude-dir=node_modules --exclude-dir=.git
# 2. find stale pins
grep -rn -E 'tomgrv/actions[^ ]*@v<old>|scripts-ref: v<old>' .github
```

1. Rename per the table.
2. Move **all** pins to the new majors **together**.
3. Re-run the installers (`feature-configure`, `zz-update`, rebuild the
   container) so deployed stubs are replaced.
4. Trigger each workflow once with `workflow_dispatch`.

## 6. Rollback

Pin the previous majors **together** (tooling, provider ref, any pinned release
action). Mixing a new provider with old tooling, or the reverse, fails at the
first renamed call. Rollback never needs a revert commit: re-pin, rerun.

## 7. Worked examples

### 7.1 The `zz-*` rename

Provider `tomgrv/scripts` renamed `zz_*` → `zz-*` and
`<verb>-json|yaml` → `json-<verb>|yaml-<verb>`, adding `json` / `yaml`
dispatchers.

| Repo                           | Before | After  |
| ------------------------------ | ------ | ------ |
| `tomgrv/scripts`               | v0.34  | v1.0.0 |
| `tomgrv/actions`               | v2.46  | v3.0.0 |
| `tomgrv/devcontainer-features` | v8.29  | v9.0.0 |
| `perspikapps/vps`              | v0.3.0 | v1.0.0 |

| Old                                                                      | New                                                                      |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------ |
| `zz_args zz_ask zz_bindir zz_call zz_colors zz_dispatch zz_input`        | `zz-args zz-ask zz-bindir zz-call zz-colors zz-dispatch zz-input`        |
| `zz_install zz_log zz_menu zz_npx zz_persist zz_prompt zz_update zz_use` | `zz-install zz-log zz-menu zz-npx zz-persist zz-prompt zz-update zz-use` |
| glob `zz_*`, `config/zz_use.json`                                        | glob `zz-*`, `config/zz-use.json`                                        |
| `normalize-json merge-json validate-json load-json`                      | `json-normalize json-merge json-validate json-load` (+ `json <sub>`)     |
| `merge-yaml`                                                             | `yaml-merge` (+ `yaml <sub>`)                                            |
| npm `@tomgrv/scripts-zz_args` …                                          | `@tomgrv/scripts-zz-args` …                                              |
| shims `zz_context zz_dist zz_edit zz_json`                               | `zz-context zz-dist zz-edit zz-json`                                     |
| pins `tomgrv/actions@v2`, `scripts-ref: v0`                              | `tomgrv/actions@v3`, `scripts-ref: v1`                                   |

Unchanged on purpose: `.zz_dist`, `config.zz_dist`, `~/.cache/zz_scripts`, the
`.zz_use` marker directory, `ZZ_*` environment variables.

Rewrite pattern used (Perl, regular files only):

```perl
my $lb = qr/(?<![A-Za-z0-9_.\$])/;   # not part of a longer identifier or a dotted name
my $la = qr/(?![A-Za-z0-9_])/;
s/${lb}zz_(args|ask|bindir|call|colors|dispatch|input|install|log|menu|npx|persist|prompt|update|use)${la}/zz-$1/g;
s/${lb}zz_\*/zz-*/g;
s/${lb}(normalize|merge|validate|load)-json${la}/json-$1/g;
s/${lb}merge-yaml${la}/yaml-merge/g;
```

Sequence actually followed: scripts merged and released (v1.0.0) → actions merged
red (release workflow bootstrapped with `./release-promote`, dry run, v3.0.0) →
devcontainer-features and vps pinned to `@v3`, merged, released → follow-up pin
PRs (`@v2`→`@v3`, `scripts-ref: v0`→`v1`, `vps` `release-main.yml` →
`release-promote@v3`) → patch releases.

### 7.2 Second example: `<verb>-feature` → `feature-<verb>` and the `zz` front door

| Old                                    | New                                                                                  |
| -------------------------------------- | ------------------------------------------------------------------------------------ |
| `install-feature`                      | `feature-install`                                                                    |
| `configure-feature`                    | `feature-configure`                                                                  |
| `resolve-context`                      | `feature-context`                                                                    |
| —                                      | `feature <sub>` dispatcher (`feature install`, …)                                    |
| —                                      | `zz <name> [args]`: runs `zz-<name>` if installed, else `zz-use -x <name> [args]`    |
| npm `@tomgrv/scripts-install-feature`… | `@tomgrv/scripts-feature-install` …                                                  |

Lessons it added to the catalogue:

- **Name a family `<family>-<verb>`.** The dispatcher then costs one `run.sh`
  (`zz-dispatch $0 "$@"`), and installers can request the whole family with one
  glob (`zz-use feature "feature-*"`) instead of an explicit list that drifts.
- **Commands outside the glob must be named explicitly** wherever the bundle is
  installed or refreshed: `setup.sh`, `zz-update`, and the `--force` rule in
  `zz-use` all needed `zz` added, because `zz-*` does not match plain `zz`.
- **Keep runtime state paths** (e.g. `.git/info/configure-feature/state`, the
  merge snapshots): they are data, like `.zz_dist`. Renaming them silently
  discards the merge base of every consumer.
- **A front door should have no dependencies** (`zz` does not even call
  `zz-log`): it is what you run when nothing else is installed yet.
