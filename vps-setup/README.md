<!-- @format -->

# vps-setup

Thin wrapper around [`zz-setup`](https://github.com/tomgrv/scripts/tree/main/zz-setup):
runs every step of this repo in order (or just the ones asked for) and prints
the final connection summary (Tailscale IP, Cockpit/Rancher credentials, etc).
Feature discovery, the skip/up/down menu, dependency resolution and the input
prompts are all `zz-setup`'s.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps). Unlike every
other feature folder, this one isn't itself an installable step, so it has no
`vps` key in its `package.json` and `zz-setup` never proposes it (like
`vps-common`). See the root README's
[One folder per feature](../README.md#one-folder-per-feature) and
[Running vps-setup](../README.md#running-vps-setup) for the full picture.

## Usage

```sh
curl -fsSL https://raw.githubusercontent.com/tomgrv/scripts/main/setup.sh | sh
zz-use perspikapps/vps/vps-setup
sudo vps-setup
```

With no arguments on an actual terminal, `vps-setup` shows `zz-setup`'s
interactive menu; piped or scripted, pass flags instead:

```sh
sudo vps-setup --only-vps-rancher
sudo vps-setup --down-vps-marketplace
sudo vps-setup -h    # zz-setup's help, listing every step
```

Legacy flags are translated: `--skip-<step>` / `--with-<step>` /
`--only-<step>` / `--down-<step>` become `zz-setup`'s `-s` / `-w` / `-o` / `-d`
lists and `--force-down` becomes `-F`; anything else (`-h`, `-S` for a status
view, `-D`) is passed through. From a checkout, no `zz-use` install is needed:

```sh
sudo bash vps-setup/run.sh --only-vps-rancher
```

## What stays here

- the Ubuntu and root checks;
- `VPS_SETUP_ENV_FILE` (default `/etc/vps-setup.env`): a shell-syntax settings
  file (what cloud-init writes) that is sourced, never rewritten;
- `VPS_SETUP_REPO_URL` / `VPS_SETUP_REPO_REF`: which fork/branch `zz-setup`
  fetches into `/opt/<repo>`; a full local checkout is used in place;
- the final connection summary: each step prints its own block through its
  `summary` action (`bash <step>/run.sh summary`, also callable on its own),
  in `vps.order`; a step without `summary()` prints nothing.

## Dependencies

`vps-common` (shared helpers) and `zz-setup` (fetches the repo, proposes the
steps, asks and persists their inputs, runs them), both fetched with `zz-use`.

## Tests

```sh
bats test.bats
```

Covers the wiring (`zz-use`, `vps-common`), the legacy-flag translation, the
settings file, fork URL handling and `package.json`'s `bin`/`dependencies`,
with `zz-setup` stubbed. Actually orchestrating a real install needs a live root
Ubuntu box - see the root README's [Tests](../README.md#tests) section.
