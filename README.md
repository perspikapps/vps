<!-- @format -->

# vps

One-line bootstrapper that turns a fresh Ubuntu VPS into a secured management
box running Cockpit and a single-node k3s/Rancher cluster, with Traefik as a
public HTTP/HTTPS ingress. Cockpit, Rancher and the Traefik dashboard are
private-access only (reachable over the Tailscale network by default); the
ingress itself (80/443) is public on purpose - see
[Security model](#security-model). The repo also publishes a Helm chart catalog
(`charts/`) that the `vps-marketplace` step registers in Rancher - see
[Rancher Marketplace](#rancher-marketplace). Every step can be turned off
again without reinstalling the others - see
[Removing a feature](#removing-a-feature-updown-per-step).

```bash
curl -fsSL https://raw.githubusercontent.com/tomgrv/scripts/main/setup.sh | sh
zz-use perspikapps/vps/vps-setup
sudo vps-setup
```

- **Line 1** installs [`zz-use`](https://github.com/tomgrv/scripts) and the core
  `zz-*` helpers onto `PATH`. It never runs anything from this repo.
- **Line 2** fetches `vps-setup`, the orchestrator.
- **Line 3** installs; it is safe to re-run at any time (every step is idempotent).

There is deliberately no single end-to-end one-liner: every folder here is
fetched and run the same way (`zz-use <org>/<repo>/<name>`, then `<name>`).

With no arguments on a terminal you get an [interactive menu](#interactive-menu);
`-h` lists every flag. Inputs can be passed as environment variables:

```bash
sudo TAILSCALE_AUTHKEY=tskey-... \
    VPS_ADMIN_USER=ops VPS_ADMIN_SSH_KEY="ssh-ed25519 AAAA..." \
    RANCHER_HOSTNAME=rancher.example.internal \
    vps-setup
```

## Contents

[Running vps-setup](#running-vps-setup) ·
[Single step](#running-a-single-step-or-a-subset) ·
[Dependencies](#dependencies-between-steps) ·
[Menu](#interactive-menu) ·
[Removing](#removing-a-feature-updown-per-step) ·
[Full example](#full-copy-paste-example) ·
[Fork or branch](#running-from-a-non-standard-branch-or-fork) ·
[Keys](#getting-the-keys-youll-need) ·
[cloud-init](#provisioning-via-cloud-init--kairos) ·
[Layout](#layout) ·
[One folder per feature](#one-folder-per-feature) ·
[Network config](#network-config-each-features-own-packagejson) ·
[Security](#security-model) ·
[Traefik](#traefik-ingress-lets-encrypt-and-the-dashboard) ·
[Logins](#cockpit-and-rancher-logins) ·
[Marketplace](#rancher-marketplace) ·
[Environment variables](#key-environment-variables) ·
[Troubleshooting](#troubleshooting-a-step-fails-or-just-stops) ·
[Tests](#tests) ·
[Replicating](#replicating-this-pattern-in-another-repo)

## Running vps-setup

`vps-setup` is a thin wrapper around
[`zz-setup`](https://github.com/tomgrv/scripts/tree/main/zz-setup), the generic
"fetch an `org/repo`, propose its workspaces and their inputs, then run them"
script: `sudo vps-setup [flags]` is `sudo zz-setup perspikapps/vps [options]`
plus the Ubuntu/root checks, the legacy flags below (translated to
`zz-setup`'s `-s`/`-w`/`-o`/`-d`/`-F`) and the final connection summary.

A `zz-use perspikapps/vps/vps-setup` only fetches the `vps-setup/` folder, so
`zz-setup` clones/updates a full checkout into `/opt/vps` on every run (run from
inside a full local checkout, `vps-setup/run.sh` uses that checkout as-is).
`VPS_SETUP_REPO_URL`/`ZZ_SETUP_REF` select the fork/branch - see
[Running from a non-standard branch or fork](#running-from-a-non-standard-branch-or-fork).

> [!NOTE]
> Upgrading from an older `vps-setup`: the checkout moved from `/opt/vps-setup`
> (`VPS_SETUP_DIR`, now gone) to `/opt/vps`, and menu answers are kept by
> `zz-persist` in `/etc/vps.env` (plain `KEY=VALUE`, `600`). `VPS_SETUP_ENV_FILE`
> is still read, but only as a shell-syntax settings file you provide; it is
> never rewritten. `/opt/vps-setup` can be deleted.

## Running a single step (or a subset)

`vps-setup` runs eight feature folders in the order of each one's
`config.order` (see [One folder per feature](#one-folder-per-feature)):
`vps-system`, `vps-tailscale`, `vps-security`, `vps-cockpit`, `vps-k3s`
(includes Traefik configuration), `vps-rancher`, `vps-dokploy` and
`vps-marketplace`. All run by default except `vps-dokploy`, which is opt-in
(`config.default: false`) because it is an alternative to the k3s stack, not an
addition to it - see [Dokploy instead of k3s](#dokploy-instead-of-k3s). Three flag families choose which run:

- **`--skip-<step>`** - run everything _except_ the named step(s).
- **`--with-<step>`** - turn on an opt-in step (a no-op on one already on).
- **`--only-<step>`** - run _only_ the named step(s); repeat to run a few. Any
  `--only-*` overrides every `--skip-*`/`--with-*`.

```bash
# Re-run just Rancher after changing RANCHER_HOSTNAME:
sudo RANCHER_HOSTNAME=new.example.com vps-setup --only-vps-rancher

# Dokploy instead of the k3s/Rancher stack:
sudo vps-setup --skip-vps-k3s --skip-vps-rancher --skip-vps-marketplace --with-vps-dokploy

# Everything except Kubernetes:
sudo vps-setup --skip-vps-rancher --skip-vps-k3s
```

This is a convenience wrapper over calling a feature's own script (see
[Layout](#layout)) that adds the repo update, dependency resolution and the
final summary. Re-running one step to pick up a changed variable is safe.

### Dependencies between steps

A feature's `package.json` `dependencies` field is the single source of truth
for what it needs: `vps-rancher` depends on `vps-k3s`, `vps-marketplace` on
`vps-rancher`. `vps-setup` resolves it
transitively, so enabling `vps-marketplace` also enables `vps-rancher` and
`vps-k3s`:

```bash
sudo vps-setup --only-vps-marketplace
# -> [vps-setup] Also enabling 'vps-rancher' (required by 'vps-marketplace').
# -> [vps-setup] Also enabling 'vps-k3s' (required by 'vps-rancher').
```

The same field is read in reverse for
[`--down-<step>`](#removing-a-feature-updown-per-step): a step is refused while
something that depends on it is still enabled. Adding a dependency is a
one-line edit to the feature's `package.json`.

## Interactive menu

`sudo vps-setup` with **no arguments**, on a terminal, shows a menu drawn by
[`zz-menu`](https://github.com/tomgrv/scripts/tree/main/zz-menu):

```
==== VPS setup menu ====
   1) [up  ] * vps-system        Base system update & essentials
   2) [up  ] * vps-tailscale     Tailscale install
   3) [up  ] * vps-security      Firewall / SSH / fail2ban hardening
   ...
   8) [up  ] * vps-marketplace   Rancher Apps & Marketplace catalog registration
  (* = installed by default) Number cycles skip -> up -> down; <enter> proceeds, q quits.
>
```

A number cycles a step through `skip -> up -> down`; **enter** proceeds, **`q`**
quits without changing anything. It builds the same selection as the flags.

A second menu then lists every input the enabled steps declare in their
`config.inputs`, with its status:

```
==== Feature inputs ====
   1) TZ                       [optional] vps-system - Timezone to set on the VPS
   ...
   7) TAILSCALE_AUTHKEY        [required] vps-tailscale - Auth key to auto-join a tailnet
  Number sets that input; <enter> proceeds with what's set, q quits.
>
```

A number asks for that input's value (never echoed back; answer empty to keep
what is set). Each answer is persisted by `zz-persist` to `/etc/vps.env`
(owner-only), so a re-run lists it as `[set]` without asking again, the same as
an input already in the environment. The menu is skipped when every input is set.

`VPS_SETUP_ENV_FILE` (default `/etc/vps-setup.env`) is a separate, optional
shell-syntax file - what cloud-init writes - that `vps-setup` sources on every
run and never rewrites; its values win over `/etc/vps.env`. A required input
still empty (e.g. `TAILSCALE_AUTHKEY`) aborts the run before any step starts:
set it, or pass `--skip-vps-tailscale`.

## Removing a feature (up/down per step)

Pass `--down-<step>` to uninstall one step without touching the rest:

```bash
sudo vps-setup --down-vps-marketplace
sudo vps-setup --down-vps-marketplace --down-vps-dokploy
```

A step whose dependent is still enabled refuses to come down:

```bash
sudo vps-setup --down-vps-k3s
# [vps-setup] Refusing to bring 'vps-k3s' down: 'vps-rancher' depends on it and is still enabled.
# [vps-setup] Also pass --down-vps-rancher, or --force-down to override (may leave 'vps-rancher' broken).
```

Either bring the dependents down in the same run (`--down-vps-k3s
--down-vps-rancher --down-vps-marketplace` removes the whole cluster), or pass
`--force-down`.

| Step                | `down` removes                                                                                          | Left in place                                                      |
| ------------------- | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| `vps-system`        | _(no down action - a base upgrade, nothing to undo)_                                                    | everything                                                         |
| `vps-security`      | ufw rules (disables ufw), sshd hardening, fail2ban jail                                                 | the admin user/password `up` created, if any                       |
| `vps-tailscale`     | logs out of the tailnet, disables `tailscaled`                                                          | the `tailscale` package (`PURGE_TAILSCALE=true` removes it too)    |
| `vps-cockpit`       | the Cockpit packages (incl. packagekit, files) and socket config                                        | -                                                                  |
| `vps-k3s`           | k3s itself - **takes Rancher and every Marketplace app (ArgoCD, Epinio, GitHub ARC, ...) down with it** | -                                                                  |
| `vps-rancher`       | the Helm release and its namespace                                                                      | cert-manager, apps installed via Apps & Marketplace                |
| `vps-dokploy`       | Dokploy, **every app it deployed** (swarm services, volumes), the swarm and `/etc/dokploy`              | Docker itself (`REMOVE_DOCKER=true` removes it too)                |
| `vps-marketplace`   | the `ClusterRepo` catalog registration only                                                             | apps already installed from it (uninstall those from Rancher's UI) |

Every feature's `run.sh` also takes the action directly (`up` is the default):

```bash
sudo sh vps-marketplace/run.sh down
```

## Full copy-paste example

A one-shot install on a fresh Ubuntu VPS, as root right after first boot
(see [Getting the keys you'll need](#getting-the-keys-youll-need)):

```bash
curl -fsSL https://raw.githubusercontent.com/tomgrv/scripts/main/setup.sh | sh
zz-use perspikapps/vps/vps-setup

VPS_ADMIN_USER=ops \
    VPS_ADMIN_SSH_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... you@laptop" \
    TAILSCALE_AUTHKEY="tskey-auth-xxxxxxxxxxxx-xxxxxxxxxxxxxxxxxxxxxxxxxxxx" \
    RANCHER_HOSTNAME="rancher.tailnet-name.ts.net" \
    RANCHER_BOOTSTRAP_PASSWORD="$(openssl rand -base64 24)" \
    vps-setup
```

This creates the `ops` sudo user with your key, disables SSH password login,
joins your tailnet and installs Cockpit, k3s and Rancher. Then, from a machine
on the same tailnet, open Cockpit (`https://<tailscale-ip>:9080`) and Rancher
(`https://rancher.tailnet-name.ts.net:7083`). The Rancher bootstrap password is
printed and also written to `/root/.vps-secrets.env`.

### "command not found" for a helper after an upgrade

`zz-use` caches downloads for 24 hours per repo and ref (`ZZ_CACHE_TTL`, in
minutes). `vps-setup` refreshes the cache for what it runs, but a copy of
`vps-setup` installed before an upgrade stays old until refreshed once:

```bash
sudo zz-use --force perspikapps/vps/vps-setup
sudo vps-setup
```

## Running from a non-standard branch or fork

Two fetches must agree: `zz-use`'s fetch of the `vps-setup` folder (`@<ref>`),
and `vps-setup`'s internal clone of the full repo
(`VPS_SETUP_REPO_URL`/`ZZ_SETUP_REF`):

```bash
BRANCH=my-feature

curl -fsSL https://raw.githubusercontent.com/tomgrv/scripts/main/setup.sh | sh
zz-use "perspikapps/vps/vps-setup@${BRANCH}"
sudo ZZ_SETUP_REF="$BRANCH" vps-setup
```

| Variable             | Default                                  | Purpose                             |
| -------------------- | ---------------------------------------- | ----------------------------------- |
| `VPS_SETUP_REPO_URL` | `https://github.com/perspikapps/vps.git` | Clone a fork instead                |
| `ZZ_SETUP_REF`       | `main`                                   | Branch, tag, or commit to check out |

For a fork, set both and fetch `vps-setup` from the fork too:

```bash
zz-use "<you>/vps/vps-setup@my-feature"
sudo VPS_SETUP_REPO_URL=https://github.com/<you>/vps.git \
    ZZ_SETUP_REF=my-feature \
    vps-setup
```

> [!WARNING]
> `export ZZ_SETUP_REF=...` then `sudo vps-setup` does **not** work: `sudo`
> resets the environment, so `vps-setup` silently falls back to `main`. Put the
> assignment on the `sudo` line (as above) or use `sudo -E` (if sudoers allows).

`vps-setup` re-fetches `/opt/vps` on every run (`git fetch` + `reset --hard`),
so new commits on the same branch are picked up. Only `zz-use`'s fetch of
`vps-setup` itself is cached; `zz-update` forces a fresh download of it.

## Getting the keys you'll need

**SSH key pair** (`VPS_ADMIN_SSH_KEY`) - generate one on your own machine, never
on the VPS:

```bash
ssh-keygen -t ed25519 -C "you@laptop" -f ~/.ssh/vps_ed25519
cat ~/.ssh/vps_ed25519.pub # paste this whole line as VPS_ADMIN_SSH_KEY
```

An existing key is usually `~/.ssh/id_ed25519.pub`; GitHub users can fetch theirs
with `curl https://github.com/<your-username>.keys`. See
[GitHub - Generating a new SSH key](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent).

**Tailscale auth key** (`TAILSCALE_AUTHKEY`) - generate it at
<https://login.tailscale.com/admin/settings/keys> ("Generate auth key"). For a
server prefer **reusable**, **ephemeral: off**, **pre-approved** (if your tailnet
requires device approval) with a short expiry. See
[Tailscale - Auth keys](https://tailscale.com/kb/1085/auth-keys). Without it,
`vps-tailscale` still installs Tailscale; run `tailscale up` manually afterwards.

**Rancher bootstrap password** (`RANCHER_BOOTSTRAP_PASSWORD`) - any string, e.g.
`openssl rand -base64 24`. If unset, `vps-rancher` generates and saves one.

## Provisioning via cloud-init / Kairos

[`cloud-init/kairos-vps-setup.yaml`](cloud-init/kairos-vps-setup.yaml) is a
`#cloud-config` user-data file that bootstraps `zz-use` and runs `vps-setup`
unattended on first boot. It works with [Kairos](https://kairos.io)
Ubuntu-flavored images (install config) and any cloud-init VPS provider that
accepts "User data" (DigitalOcean, Hetzner Cloud, OpenStack, ...).

1. Copy the file and fill in the placeholders: your SSH public key (in two
   places - `users[].ssh_authorized_keys` and `VPS_ADMIN_SSH_KEY`), the
   Tailscale auth key and `RANCHER_HOSTNAME`.
2. Paste it into the provider's "User data" field (or pass it to Kairos).
3. On first boot the VPS installs itself; progress is in `/var/log/vps-setup.log`.

`runcmd` already runs as root, so no `sudo` is needed there.

## Layout

| Path                  | Role                                                                                                                                                         |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `vps-setup/`          | Orchestrator: a thin [`zz-setup`](https://github.com/tomgrv/scripts/tree/main/zz-setup) wrapper plus the connection summary. Not a step.                     |
| `vps-network/`        | Script (not a step): public/private addresses, private interface, wildcard domain, port lookup, `verify` from outside. Called by the steps, never sourced.   |
| `vps-cert-manager/`   | Script (not a step): installs cert-manager through Helm unless it is there. Called by `vps-rancher`.                                                          |
| `vps-system/`         | apt update/upgrade, base tooling, unattended security upgrades.                                                                                              |
| `vps-security/`       | Optional admin user, ufw rules generated from every feature's ports, sshd hardening, fail2ban, Cockpit/console password.                                     |
| `vps-tailscale/`      | Installs Tailscale, enables `tailscaled`, joins the tailnet.                                                                                                 |
| `vps-cloudflare/`     | Opt-in Cloudflare Tunnel + WARP private routes as the private network; mutually exclusive with `vps-tailscale` - see [Private access](#private-access). |
| `vps-cockpit/`        | Installs Cockpit (plus packagekit and files modules) on ports 9080/9083.                                                                                                                         |
| `vps-k3s/`            | k3s (Traefik enabled), kubectl, Helm; Traefik as public ingress - see [Traefik](#traefik-ingress-lets-encrypt-and-the-dashboard).                            |
| `vps-rancher/`        | cert-manager and Rancher via Helm on ports 7080/7083. Depends on `vps-k3s`.                                                                                  |
| `vps-dokploy/`        | Opt-in [Dokploy](https://dokploy.com) (Docker, Swarm, Traefik) via its official installer; an alternative to `vps-k3s` - see [Dokploy instead of k3s](#dokploy-instead-of-k3s). |
| `vps-coder/`          | Opt-in [Coder](https://coder.com) via helm, following its [Rancher guide](https://coder.com/docs/install/server/rancher): Bitnami PostgreSQL, the upstream chart exposed through Traefik (public). Depends on `vps-rancher`. |
| `vps-marketplace/`    | Registers `charts/` as a Rancher `ClusterRepo` - see [Rancher Marketplace](#rancher-marketplace). Depends on `vps-rancher`.                                  |
| `charts/`             | Helm charts for apps that run on the cluster (ArgoCD, Epinio, Cognee, Coder, Hermes Agent, Infisical, GitHub ARC). No `run.sh`; installed from Rancher's UI. |
| `cloud-init/`         | First-boot user-data - see [cloud-init](#provisioning-via-cloud-init--kairos).                                                                               |
| `tests/`              | Invariants spanning every folder - see [Tests](#tests).                                                                                                      |
| `package.json` (root) | npm workspaces root listing every top-level folder, for tooling (`npm ls`, lint-staged, commitlint scopes). `vps-setup` itself needs no npm.                 |

There is no root `setup.sh`: the one-liner bootstraps
[`tomgrv/scripts`'s own `setup.sh`](https://github.com/tomgrv/scripts/blob/main/setup.sh).
Pin its ref with `ZZ_ORIGIN_REF` (default `main`) or bootstrap from a fork with
`ZZ_ORIGIN`.

A single feature can also be run without this repo or `vps-setup`:

```sh
curl -fsSL https://raw.githubusercontent.com/tomgrv/scripts/main/setup.sh | sh
command -v jq > /dev/null || sudo apt-get update && sudo apt-get install -y jq # the scripts need it
zz-use perspikapps/vps/vps-rancher
sudo vps-rancher up
```

`zz-use` downloads this repo (cached per origin/ref) and links
`vps-rancher/run.sh` onto `PATH`, where `sudo vps-rancher up` runs it. Inside a
checkout, `sudo RANCHER_HOSTNAME=... zz-setup ./ -o vps-rancher` (`-d` to bring it
down) skips the menu but keeps dependency auto-enable, requirements and inputs.

## One folder per feature

Each feature is a small npm workspace package. All of these are required here:

```
vps-rancher/
  package.json   # see below
  run.sh         # up(), down() (and summary()) functions, dispatched on the first argument
  test.bats      # syntax + shape checks
  README.md      # env vars, up/down usage, dependencies
```

```json
{
  "name": "@tomgrv/vps-rancher",
  "version": "1.0.0",
  "private": true,
  "description": "Rancher install",
  "bin": { "vps-rancher": "run.sh" },
  "engines": { "zz-setup": "*" },
  "config": { "order": 5, "default": true, "requires": { "root": true, "os": "ubuntu" } },
  "dependencies": { "@tomgrv/vps-k3s": "*" }
}
```

| Field              | Meaning                                                                                                                                                                                                                    |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `name`             | Always `@tomgrv/<folder>`. Internal identities (flags, state, `--only-vps-rancher`) use the name without the scope, keeping the `vps-` prefix.                                                                             |
| `bin`              | `{"<folder>": "run.sh"}`. With `engines.zz-setup`, it makes the folder a runnable step: `zz-setup` runs the bin with `up` or `down`.                                                                                       |
| `engines.zz-setup` | Marks the package runnable by `zz-setup` (any value, `"*"` by convention). `vps-setup`, `vps-network` and `vps-cert-manager` omit it, so they are never proposed as steps.                                                                      |
| `config`           | Optional settings: `order` (install order, an integer), `default` (`false` = opt-in), `inputs` (see [Interactive menu](#interactive-menu)), `ports` (see [Network config](#network-config-each-features-own-packagejson)). |
| `config.summary`   | `true` when the bin answers a `summary` action (the connection info it prints); `zz-setup <repo> -m` collects them, which is how `vps-setup` prints its final block. |
| `config.requires`  | What the host must offer, checked before the first step runs: `{"root": true, "os": "ubuntu"}`. |
| `dependencies`     | Any other step it needs. Only keys naming a real step folder count, so an ordinary npm dependency is never auto-enabled.                                                        |

Folder names carry no ordering (`vps-rancher/`, not `05-vps-rancher/`); order is
`config.order`. The uniform `vps-` prefix also avoids collisions with real
binaries: `zz-use` installs `<name>/run.sh` under the literal folder name, so a
plain `tailscale/` would shadow the real `tailscale` CLI.

**Adding a feature:** create `vps-whatever/` with the four files above (copy an
existing feature's `test.bats`), choose a `config.order`, and add the folder to
the root `package.json` `workspaces`. `vps-setup` picks it up automatically.
**Removing one:** delete the folder and that entry.

`vps-setup` reads these fields with `jq` (installed on demand by `zz-setup`,
since this can run before `vps-system` on a fresh box), so it needs no npm.

## Network config (each feature's own `package.json`)

Every port this repo opens is declared on the feature that owns it, in
`config.ports`:

```json
{
  "name": "rancher_http",
  "port": 7080,
  "access": "private",
  "note": "optional, becomes the ufw rule's comment"
}
```

`access` is `"private"` or `"public"` (see [Private access](#private-access)).
`vps-rancher` carries `rancher_http`/`rancher_https`, `vps-k3s` carries
`http`/`https`/`traefik_dashboard`, and so on.

`vps-security` has no per-service ufw logic: it calls `vps-network ports`, which
scans every step's `package.json`, and builds the rules
from the combined list. Features that bind a port read it through
`vps-network port <name>` (zz-setup also exports it as `<NAME>_PORT`), so the port ufw opens and the port the app listens on cannot drift.

To change a default for good, edit that `package.json` and re-run the affected
steps (e.g. `--only-vps-security --only-vps-rancher`). To override for one run,
set the env var: the entry's `name`, upper-cased, plus `_PORT` (`rancher_http`
-> `RANCHER_HTTP_PORT`, `ssh` -> `SSH_PORT`).

## Security model

Only SSH and HTTP/HTTPS (Traefik's ingress) are reachable from the internet.
Everything else - Cockpit, Rancher, the Traefik dashboard, the k3s API - is
bound by `ufw` to the private interface (see [Private access](#private-access)),
by default `tailscale0`, so you must join the same tailnet. Apps installed from
the Marketplace manage their own exposure: check each chart's `README.md` under
[`charts/`](charts/) first.

ufw alone does not hold that line for ports that k3s (ServiceLB: Rancher, the
Traefik dashboard) or Docker (the Dokploy UI) publish: they are DNAT-ed through
the FORWARD chain, which both accept ahead of ufw. `vps-security` therefore also
installs `vps-private-ports-guard.service`, which drops DNAT-ed connections to
every `access: private` port arriving on the default-route interface (unless
that interface is the private one). `vps-k3s`, `vps-rancher` and `vps-dokploy`
re-apply it once they are up. IPv4 only. To verify, from outside the private
network: `curl -m 5 http://<public-ip>:<private-port>` must time out.

HTTP/HTTPS are public unconditionally: Traefik is the VPS's real ingress, and
Let's Encrypt's HTTP-01 challenge needs port 80 reachable to issue certificates.

`TAILSCALE_AUTHKEY` is a required input of `vps-tailscale` alone, so `vps-setup`
aborts before any step runs if that step is enabled and the key is unset. Pass
`--skip-vps-tailscale` to run without it and provide another network instead.

### Private access

Only `vps-tailscale` knows about Tailscale. The other steps only know that some
ports are `"access": "private"` and which interface carries the private network:

- `vps-tailscale` persists `VPS_PRIVATE_INTERFACE=tailscale0` (to
  `/etc/vps-private-access.env`, owner-only) on install and removes it on `down`.
  It runs before `vps-security` for that reason.
- `vps-security` opens every private port on that interface only, and the final
  summary shows its address. With no interface, private ports stay closed.
- `vps-cloudflare` (opt-in) is the alternative provider: it persists
  `VPS_PRIVATE_INTERFACE=vpscf0`, a dummy interface holding the address WARP
  clients reach through a Cloudflare Tunnel private network route. It is
  **mutually exclusive** with `vps-tailscale` (`config.conflicts` on both sides,
  and `up` refuses on a host already set up with Tailscale):
  `sudo vps-setup --skip-vps-tailscale --with-vps-cloudflare`. See
  [`vps-cloudflare`](vps-cloudflare/README.md).
- For another network (WireGuard, a LAN NIC...) skip the Tailscale step and set
  the variable yourself: `sudo VPS_PRIVATE_INTERFACE=wg0 vps-setup
--skip-vps-tailscale`. It also works as a menu input and from
  `VPS_SETUP_ENV_FILE`; a set variable wins over the persisted value.
- Steps read it through `vps-network private-interface` and `vps-network private-address`.

## Traefik ingress: Let's Encrypt and the dashboard

`vps-k3s` keeps k3s's bundled Traefik and configures it as the public ingress
through a `HelmChartConfig` (k3s's override mechanism, re-applied safely any
time, e.g. `--only-vps-k3s`).

- **Public HTTP/HTTPS, any hostname.** Ports 80/443 are Traefik's `web`/
  `websecure` defaults, exposed by k3s's ServiceLB; only ufw needs them open.
  Traefik routes by the request's `Host` header, so any hostname pointed at the
  VPS is served by whichever `Ingress` declares it (including per-app
  subdomains of Marketplace apps such as Epinio).
- **Let's Encrypt.** A certResolver named `letsencrypt` is configured (email from
  `TRAEFIK_ACME_EMAIL`, HTTP-01 on `web`, state on a PVC so certs survive pod
  restarts). It issues nothing by itself: annotate an `Ingress` (or
  `IngressRoute`) with `traefik.ingress.kubernetes.io/router.tls.certresolver:
letsencrypt` and point real DNS at the VPS. Each hostname gets its own cert on
  demand; wildcards need DNS-01, which is not wired up.
- **Staging by default.** `TRAEFIK_ACME_STAGING` defaults to `true` (Let's
  Encrypt staging: untrusted certs, no rate limit). Set it to `false` for real
  certs once Ingress and DNS work; production has strict per-domain limits.
- **Dashboard.** On `TRAEFIK_DASHBOARD_PORT` (default `8088`), private-access, at
  `http://<private-ip>:8088/dashboard/` (trailing slash required). It has no
  login of its own, which is acceptable only because it is gated to the tailnet;
  never put it on a public port.

## Dokploy instead of k3s

`vps-dokploy` (opt-in) installs [Dokploy](https://dokploy.com) with its official
installer: Docker, a single-node Swarm, Postgres and Dokploy's own Traefik.
`vps-k3s` and `vps-dokploy` are **mutually exclusive on one host**, both want
Traefik on ports 80/443, so pick one ingress per VPS:

```bash
sudo vps-setup --skip-vps-k3s --skip-vps-rancher --skip-vps-marketplace --with-vps-dokploy
```

Selecting both aborts `zz-setup` before any step runs (`config.conflicts`), and
`vps-dokploy` also refuses to run while k3s is installed (the installer's own port
check cannot see k3s's ServiceLB rules) and while the host is in a swarm that is
not Dokploy's (the installer starts with `docker swarm leave --force`).

The admin UI (port 3000) is `private`, enforced by the same
[FORWARD guard](#security-model) as Rancher and the Traefik dashboard - see
[`vps-dokploy`](vps-dokploy/README.md#access-and-security).

## Cockpit and Rancher logins

- **Cockpit** authenticates through PAM against a real Linux account, separate
  from SSH (which stays key-only). `vps-security` sets a password for
  `VPS_ADMIN_USER` (or `root`): `VPS_ADMIN_PASSWORD` if set, otherwise a random
  one saved to `/root/.vps-secrets.env` (`COCKPIT_ADMIN_USER`,
  `COCKPIT_ADMIN_PASSWORD`).
- **Rancher** user is always `admin`; the initial password is
  `RANCHER_BOOTSTRAP_PASSWORD` if set, otherwise a random one saved to
  `/root/.vps-secrets.env`. Rancher asks you to change it on first login.

Marketplace apps set up their own login; see their chart's `README.md`.

## Rancher Marketplace

Extra apps that run _on_ the cluster (ArgoCD, Epinio, GitHub Actions Runner
Controller, ...) are not installed by `vps-setup`. This repo publishes them as a
Helm chart repo from [`charts/`](charts/), and the `vps-marketplace` step (on by
default) registers it as a Rancher `ClusterRepo` named `perspikapps-vps`
(`https://perspikapps.github.io/vps/`), visible under **Apps & Marketplace →
Repositories**. Install or remove apps from **Apps & Marketplace → Charts** like
any catalog app; `charts/<name>/README.md` lists the required values.
`vps-marketplace down` removes only the registration.

**Why the split.** `vps-cockpit` and `vps-dokploy` configure the host (apt
packages, systemd, Docker), which a chart cannot do. The cluster apps are ordinary
Kubernetes workloads, so a Rancher-native catalog gives install/upgrade/values
UI, version pinning and easy removal for free.

**Publishing.** `charts/<name>/` are usually thin umbrella charts (a `Chart.yaml`
dependency on the upstream chart plus a `values.yaml` with sane defaults; see
[`charts/argocd`](charts/argocd), [`charts/epinio`](charts/epinio),
[`charts/github-arc`](charts/github-arc), which pins two upstream charts). Apps
with no upstream Helm chart, only a Docker Compose deploy, ship their own
templates ([`charts/cognee`](charts/cognee)).
`.github/workflows/publish-charts.yml` packages every chart and publishes them
(via [`helm/chart-releaser-action`](https://github.com/helm/chart-releaser-action))
as GitHub Releases plus an `index.yaml` on `gh-pages` whenever `charts/**`
changes on `main`; GitHub Pages serves that branch. To add an app: add
`charts/<name>/Chart.yaml` + `values.yaml` (+ `README.md` documenting required
values) and push to `main`; it is live within minutes.

Cockpit and Rancher credentials are printed by `vps-setup` at the end of an
install; Marketplace apps print theirs as their own chart notes describe.

## Key environment variables

`*_PORT` variables are per-run overrides of a default that lives in the owning
feature's `config.ports` (see [Network config](#network-config-each-features-own-packagejson)).
Each feature's README lists its own variables in full.

| Variable                                   | Default                              | Purpose                                                                                                           |
| ------------------------------------------ | ------------------------------------ | ----------------------------------------------------------------------------------------------------------------- |
| `VPS_ADMIN_USER`                           | unset                                | Create this sudo user                                                                                             |
| `VPS_ADMIN_SSH_KEY`                        | unset                                | Authorized key for the admin user and root                                                                        |
| `VPS_ADMIN_PASSWORD`                       | random                               | Cockpit/console login password (separate from SSH)                                                                |
| `SSH_PORT`                                 | `22`                                 | SSH port kept open publicly                                                                                       |
| `TAILSCALE_AUTHKEY`                        | unset                                | Auto-join a tailnet (**required** unless `--skip-vps-tailscale`)                                                  |
| `TAILSCALE_EXTRA_ARGS`                     | unset                                | Extra flags appended to `tailscale up`                                                                            |
| `CLOUDFLARE_TUNNEL_TOKEN`                  | unset                                | Tunnel token for `vps-cloudflare` (**required** when that opt-in step is selected)                                |
| `CLOUDFLARE_PRIVATE_IP`                    | `10.254.254.1`                       | Address WARP clients use to reach the VPS through the tunnel                                                      |
| `CODER_ADMIN_EMAIL` / `CODER_ADMIN_USERNAME`  | `admin@<wildcard domain>` / `admin`  | First Coder admin (`vps-coder`; password generated and saved)                                                     |
| `DEVCONTAINER_REGISTRY_USER` / `_ORG` / `_TOKEN` | unset                          | External registry for `vps-coder`'s devcontainer-builder; unset = in-cluster registry |
| `CODER_WORKSPACE_NAMESPACE`                | `coder-workspaces`                   | Namespace Coder workspaces run in (`vps-coder` creates it and grants Coder rights there)                          |
| `CODER_ACCESS_URL`                         | `http://coder.<wildcard domain>`     | URL of Coder (`vps-coder`, through Traefik)                                                                       |
| `WILDCARD_DOMAIN`                          | unset (nip.io fallback)              | Wildcard DNS domain for apps needing subdomains, read by `vps-coder` (set in `vps-system`)                        |
| `COCKPIT_HTTP_PORT` / `COCKPIT_HTTPS_PORT` | `9080` / `9083`                      | Cockpit ports                                                                                                     |
| `RANCHER_HTTP_PORT` / `RANCHER_HTTPS_PORT` | `7080` / `7083`                      | Rancher ports                                                                                                     |
| `RANCHER_HOSTNAME`                         | private IP, else node IP             | Hostname used in Rancher's cert                                                                                   |
| `RANCHER_BOOTSTRAP_PASSWORD`               | random                               | Rancher initial admin password                                                                                    |
| `RANCHER_CHART_REPO_URL`                   | community `latest` channel           | Helm repository for the Rancher chart, e.g. SUSE Rancher Prime (`https://charts.rancher.com/server-charts/prime`) |
| `CERT_MANAGER_VERSION`                     | latest                               | Pin cert-manager's chart version (installed by `vps-rancher`)                                                     |
| `DOKPLOY_VERSION`                          | latest stable                        | Dokploy release tag to install (`vps-dokploy`)                                                                    |
| `ADVERTISE_ADDR`                           | host's first IPv4                    | Address Docker Swarm advertises (`vps-dokploy`)                                                                   |
| `DOCKER_SWARM_INIT_ARGS`                   | unset                                | Extra `docker swarm init` flags, e.g. a non-clashing `--default-addr-pool` (`vps-dokploy`)                        |
| `REMOVE_DOCKER`                            | `false`                              | Also remove Docker itself when `vps-dokploy` comes down                                                           |
| `TRAEFIK_ACME_EMAIL`                       | placeholder                          | Let's Encrypt contact email - set a real address                                                                  |
| `TRAEFIK_ACME_STAGING`                     | `true`                               | Let's Encrypt staging (untrusted, no rate limit) vs. production certs                                             |
| `TRAEFIK_DASHBOARD_PORT`                   | `8088`                               | Traefik dashboard port (private-access)                                                                           |
| `MARKETPLACE_REPO_NAME`                    | `perspikapps-vps`                    | Name of the Rancher `ClusterRepo` registered by `vps-marketplace`                                                 |
| `MARKETPLACE_REPO_URL`                     | `https://perspikapps.github.io/vps/` | URL of the Helm chart catalog to register                                                                         |

Ports follow a per-app range: Cockpit `9xxx`, Rancher `7xxx`, Traefik dashboard
`8xxx`; the ingress is always 80/443. Marketplace apps configure their own ports
through their chart values.

## Troubleshooting: a step fails or "just stops"

Every step runs under `set -eu`; `zz-setup` reports the first failing step with its
script and exit status, then stops.

During a full `vps-setup` run, a failing step also prints how to re-run just it:

```
[vps-setup] Step 'Rancher install' (vps-rancher/run.sh up) failed (exit 1) - see the error above. Fix it and re-run just this step with: sudo vps-setup --only-vps-rancher
```

A step that stops with no output at all usually means a _prerequisite_ was
skipped, e.g. `--only-vps-rancher` on a box where `vps-k3s` never ran, so
`kubectl`/`helm` do not exist. `vps-rancher` and `vps-marketplace` check for
those and `die` with a clear message; if you hit a silent stop elsewhere, open an
issue with the command and the last lines of output.

## Tests

```sh
npm install --global bats # or: apt-get install bats
npm test                  # or: bats --recursive .
```

The `zz-*` and `kube-*` scripts must be on `PATH` (the `setup.sh` one-liner installs
them); otherwise tests that call them fail.

Each feature folder has its own `test.bats` (run with `bats <name>/test.bats` or
that folder's `npm test`) covering `run.sh` syntax (`dash -n`), the `zz-use` line,
the functions `zz-setup` calls, and the `package.json`
`bin`/`engines`/`config`/`dependencies` shape.
[`vps-network/test.bats`](vps-network/test.bats) also covers its commands (ports,
private interface, wildcard domain) against a fixture tree.
[`tests/`](tests/) holds invariants spanning every folder (e.g. no leftover
`log`/`warn`/`die` wrappers - see [`tests/test-syntax.bats`](tests/test-syntax.bats)).
The installs themselves (apt/Helm/k3s) need a live root Ubuntu box, so that part
has no automated coverage.

## Replicating this pattern in another repo

This repo, [`tomgrv/devcontainer-features`](https://github.com/tomgrv/devcontainer-features)'
`common-utils` and [`tomgrv/scripts`](https://github.com/tomgrv/scripts) share one
shape: a normal codebase that is also a `zz-use`-installable source of scripts.

1. **One top-level folder per script**, each an npm workspace package:
   `<name>/package.json` + `<name>/run.sh` (+ optional `README.md`, `test.bats`).
   `zz-use org/repo/<name>` only works if `<name>/run.sh` sits directly under the
   repo root. `package.json` needs a `"name"` and `"bin": {"<name>": "run.sh"}`
   (for npm tooling and `zz-setup`; `zz-use` itself installs under the literal
   folder name and ignores `bin`).
2. **No root `setup.sh` of your own.** Bootstrap `zz-use` from
   [`tomgrv/scripts`'s `setup.sh`](https://github.com/tomgrv/scripts/blob/main/setup.sh)
   (one copy to maintain, nothing repo-specific). A "run everything" orchestrator
   (here `vps-setup`) is an ordinary `<name>/` folder, fetched and run as its own
   step. Individual scripts assume `zz-use` is already on `PATH` (e.g. via
   `tomgrv/actions/setup-scripts` in CI) and do not bootstrap it themselves.
3. **A shared `common/` folder** for logic several scripts need, sourced with
   `zz-use <org>/<repo>/common; . common` rather than a relative path, so it
   resolves the same from a checkout, standalone or `zz-use`-installed. Leave out
   of discovery anything that is not an installable unit; here that is the
   absence of `engines.zz-setup`.
4. **Root `package.json`** as an npm workspaces root listing every folder
   explicitly (not a glob), so `npm ls` understands the graph and sibling
   `"dependencies"` resolve.
5. **Tests:** at minimum `sh -n`/`bash -n` on every script; `bats` for pure
   logic. Say plainly what needs a live target and has no coverage.

## Upgrading

Breaking renames and major bumps: see [`UPGRADING.md`](UPGRADING.md) (order of
operations across repos, pins, pitfalls, rollback).
