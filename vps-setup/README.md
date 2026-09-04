<!-- @format -->

# vps-setup

Interactive/flag-driven orchestrator: resolves dependencies, runs every
enabled step's `up`/`down` in order, prompts for any input a step needs
that isn't already set, then prints the final connection summary
(Tailscale IP, Cockpit/Rancher credentials, etc).

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps). Unlike
every other feature folder, this one isn't itself an installable step -
it drives all the others - so it's excluded from feature discovery (like
`vps-common`) and doesn't end with `dispatch_action`. See the root
README's [One folder per feature](../README.md#one-folder-per-feature)
for the shape every folder here follows, and
[Running vps-setup](../README.md#running-vps-setup) for the full flag
reference.

## Usage

```sh
curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/setup.sh | sh
zz_use perspikapps/vps/vps-setup
sudo vps-setup
```

With no arguments on an actual terminal, `vps-setup` shows an interactive
menu; piped or scripted, pass flags instead:

```sh
sudo vps-setup --only-vps-rancher
sudo vps-setup --down-vps-marketplace
sudo vps-setup -h    # full flag list, generated from every step's own package.json
```

Or directly, from a checkout (no `zz_use` install needed):

```sh
sudo bash vps-setup/run.sh --only-vps-rancher
```

## Why this needs a full checkout

A single `zz_use perspikapps/vps/vps-setup` only fetches this one folder,
but orchestrating every step means reading every sibling folder's
`package.json`/`run.sh`. `run.sh` detects which case it's in: run from
inside a full local checkout (this repo cloned, or `vps-common/` sitting
right next to it), it uses that directory directly; run standalone (the
`zz_use`-installed case), it clones/updates a full checkout into
`VPS_SETUP_DIR` (default `/opt/vps-setup`) first - same `VPS_SETUP_REPO_URL`/
`VPS_SETUP_REPO_REF`/`VPS_SETUP_DIR` env vars as every other step reads
for pinning a fork/branch.

## Dependencies

`vps-common` (shared helpers). Not itself a dependency target for any
other step (it isn't a "step" - see above), so the auto-enable logic it
runs for other steps doesn't apply to it.

## Tests

```sh
bats test.bats
```

Covers `run.sh`/`steps.sh` syntax and static shape (the `zz_use`/
`vps-common` wiring, the feature-discovery exclusion, sourcing `steps.sh`)
plus `package.json`'s `bin`/`dependencies` fields. Actually orchestrating
a real install needs a live root Ubuntu box with every other step's
dependencies available - see the root README's
[Tests](../README.md#tests) section for the full picture.
