<!-- @format -->

# vps

One-line bootstrapper that turns a fresh Ubuntu VPS into a secured
management box running Cockpit and a single-node k3s/Rancher cluster,
with Traefik as a public HTTP/HTTPS ingress. Cockpit, Rancher, ArgoCD,
and the Traefik dashboard are Tailscale-only; the ingress itself (80/443)
is public on purpose - see [Security model](#security-model). ArgoCD and
[Epinio](#epinio-deploy-apps-from-source), and
[GitHub ARC](#github-actions-runner-controller-arc) are optional, opt-in steps (see
[Running a single step](#running-a-single-step-or-a-subset)) - everything
else runs by default. Every step can also be turned back off later without
reinstalling anything else - see [Removing a feature](#removing-a-feature-updown-per-step).

```bash
curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/dispatch.sh | sudo sh
```

Run it with no arguments on an actual terminal (not piped from `curl`) and
you get an interactive menu instead of having to remember flag names - see
[Interactive menu](#interactive-menu). Run with `-h` for the full flag
list (`--skip-tailscale`, `--skip-rancher`, etc.), or set env vars
beforehand, e.g.:

```bash
sudo TAILSCALE_AUTHKEY=tskey-... \
    VPS_ADMIN_USER=ops VPS_ADMIN_SSH_KEY="ssh-ed25519 AAAA..." \
    RANCHER_HOSTNAME=rancher.example.internal \
    sh dispatch.sh
```

## Running a single step (or a subset)

`dispatch.sh` runs ten feature folders, in the order each one's
`package.json` declares (`vps.order` - see
[One folder per feature](#one-folder-per-feature)): `system`, `security`,
`tailscale`, `cockpit`, `k3s` (includes Traefik configuration), `rancher`,
`dockermanager`, `argocd`, `epinio`, and `github-arc`. All of them run by
default **except `argocd`, `epinio`, and `github-arc`, which are opt-in**
(all three are heavy

- see their own sections below - Epinio specifically is of little use
  without a real domain, and `github-arc` needs a GitHub App already set
  up). Three flag families control which of them run:

- **`--skip-<step>`** - run everything _except_ the named step(s).
- **`--with-<step>`** - turn on an opt-in step (currently `argocd`,
  `epinio`, or `github-arc`) that's off by default; harmless (a no-op) on
  a step that's already on by default.
- **`--only-<step>`** - run _only_ the named step(s), regardless of its
  default; pass it more than once to run a few together. Any `--only-*`
  flag overrides every `--skip-*`/`--with-*` flag on the command line.

When you already have `dispatch.sh` on disk (e.g. after the
[full copy-paste example](#full-copy-paste-example)'s `-o /tmp/dispatch.sh`
download), pass flags after the filename like any script:

```bash
# Re-run just Rancher, e.g. after changing RANCHER_HOSTNAME:
sudo RANCHER_HOSTNAME=new.example.com sh /tmp/dispatch.sh --only-rancher

# Re-run Cockpit and the dockermanager plugin together, skipping everything else:
sudo sh /tmp/dispatch.sh --only-cockpit --only-dockermanager

# Full run except Rancher (e.g. you're not using Kubernetes on this box):
sudo sh /tmp/dispatch.sh --skip-rancher --skip-k3s

# Full default run, plus the opt-in ArgoCD step:
sudo sh /tmp/dispatch.sh --with-argocd
```

> [!WARNING]
> **With the piped one-liner (`curl ... | sudo sh`), you cannot just
> append flags after `sh`** - `sudo sh --only-rancher` fails with
> `sh: --only-rancher: invalid option`, because the shell parses
> `--only-rancher` as an option _to the shell itself_ (it looks like one:
> `--only-rancher` starts with `--`, same shape as `sh`'s own
> `--posix`/etc.), not as an argument to hand the script being read from
> stdin. You must add `-s --` first: `-s` tells the shell to read the
> script from stdin, and `--` marks the end of the shell's own options so
> everything after it is passed through as `$1`, `$2`, ... to `dispatch.sh`:
>
> ```bash
> curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/dispatch.sh \
>     | sudo sh -s -- --only-rancher
> ```
>
> This composes with env vars the usual way (see the
> [sudo env-var gotcha](#running-from-a-non-standard-branch-or-fork)
> above - put them on the `sudo` line, not in a plain `export`):
>
> ```bash
> curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/dispatch.sh \
>     | sudo RANCHER_HOSTNAME=new.example.com sh -s -- --only-rancher
> ```

This is equivalent to (and a convenience wrapper around) invoking a
feature's own script directly, as shown in [Layout](#layout) below -
`--only-rancher` just means "run `rancher/run.sh` through
`dispatch.sh`'s usual repo clone/update, dependency resolution, and final
summary, instead of calling it by hand." Because every feature's script
is idempotent, re-running a single step to pick up a changed env var
(like `RANCHER_HOSTNAME` above) is safe and won't disturb the others. See
`-h`/`--help` for the full flag list.

### Dependencies between steps

Every feature is its own npm workspace package under `<name>/`,
and its `package.json`'s standard `dependencies` field is the single
source of truth for what it needs - `rancher/package.json`
declares `"@tomgrv/vps-k3s": "*"`, as do `argocd`'s, `epinio`'s, and
`github-arc`'s. `dispatch.sh`
reads that field directly (no separate config to keep in sync): enabling
any of them auto-enables `k3s` too, even if you didn't ask for it
explicitly:

```bash
# k3s isn't named here, but this still installs it - rancher needs it:
sudo sh dispatch.sh --only-rancher
# -> [vps-setup] Also enabling 'k3s' (required by 'rancher').
```

The same `dependencies` field is read in reverse for
[`--down-<step>`](#removing-a-feature-updown-per-step): bringing `k3s`
down while `rancher`/`argocd`/`epinio` are still enabled is refused, since
it would leave them broken. Adding a new dependency for a feature is a
one-line edit to its `package.json` - see
[One folder per feature](#one-folder-per-feature) below.

## Interactive menu

Run `dispatch.sh` with **no arguments**, on an actual terminal (an SSH
session, not `curl ... | sudo sh`, which pipes the script itself into
stdin and never triggers this), to get a menu instead of having to
remember flag names:

```bash
sudo sh /tmp/dispatch.sh
```

```
==== VPS setup menu ====
   1) * system         [up  ] Base system update & essentials
   2) * security        [up  ] Firewall / SSH / fail2ban hardening
   3) * tailscale        [up  ] Tailscale install
   4) * cockpit          [up  ] Cockpit install
   5) * k3s              [up  ] k3s / kubectl / helm install (includes Traefik configuration)
   6) * rancher          [up  ] Rancher install
   7) * dockermanager    [up  ] cockpit-packagekit/files/dockermanager install
   8)   argocd           [skip] ArgoCD install
   9)   epinio           [skip] Epinio install
  10)   github-arc       [skip] GitHub Actions Runner Controller (ARC) install
  (* = installed by default) Enter a number to cycle
  skip -> up -> down -> skip for that step.
  <enter> to proceed, 'q' to quit without changing anything.
>
```

Type a step's number to cycle it through `skip -> up -> down -> skip`
(`down` means uninstall it - see the next section), press **enter** to
proceed with whatever you've selected, or **`q`** to quit without changing
anything. This is purely a friendlier way to build the same `--skip-*`
/ `--with-*` / `--down-*` selection described above - everything below
about flags, env vars, and dependencies applies whether you got there via
the menu or the command line.

## Removing a feature (up/down per step)

Every step can be brought back down (uninstalled/disabled) independently,
without touching anything else already on the box - pass `--down-<step>`
instead of installing it:

```bash
# Remove ArgoCD only (Rancher, k3s, Cockpit, etc. are untouched):
sudo sh /tmp/dispatch.sh --down-argocd

# Remove more than one step in the same run:
sudo sh /tmp/dispatch.sh --down-argocd --down-epinio --down-github-arc

# Add ArgoCD and remove Epinio in the same run:
sudo sh /tmp/dispatch.sh --with-argocd --down-epinio
```

A step whose dependency is still enabled refuses to come down, so you
don't accidentally break something still running:

```bash
sudo sh /tmp/dispatch.sh --down-k3s
# [vps-setup] Refusing to bring 'k3s' down: 'rancher' depends on it and is still enabled.
# [vps-setup] Also pass --down-rancher, or --force-down to override (may leave 'rancher' broken).
```

Either bring the dependent step down in the same run (`--down-k3s
--down-rancher --down-argocd --down-epinio --down-github-arc`, to remove
the whole cluster cleanly), or pass `--force-down` if you really want to
pull `k3s` out from under something still enabled.

What each step's `down` action actually does - and doesn't - undo:

| Step            | `down` removes                                                                                 | Left in place                                                            |
| --------------- | ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `system`        | _(no down action - a base package upgrade, nothing to undo)_                                   | everything                                                               |
| `security`      | ufw rules (disables ufw entirely), sshd hardening, fail2ban jail                               | the admin user/password `up` created, if any                             |
| `tailscale`     | logs out of the tailnet, disables `tailscaled`                                                 | the `tailscale` package itself (`PURGE_TAILSCALE=true` to remove it too) |
| `cockpit`       | the Cockpit packages and socket config                                                         | nothing else depends on it                                               |
| `k3s`           | k3s itself (via its own uninstaller) - **takes Rancher/ArgoCD/Epinio/GitHub ARC down with it** | -                                                                        |
| `rancher`       | the Helm release and its namespace                                                             | cert-manager (shared with Epinio)                                        |
| `dockermanager` | cockpit-dockermanager, cockpit-packagekit, cockpit-files                                       | Docker itself (`REMOVE_DOCKER=true` to also remove it)                   |
| `argocd`        | the Helm release and its namespace                                                             | k3s, cert-manager                                                        |
| `epinio`        | the Helm release, its namespace, and the `epinio` CLI                                          | k3s, cert-manager, Traefik                                               |
| `github-arc`    | both Helm releases (controller and runner scale set), the GitHub App secret, and the namespace | k3s                                                                      |

Each feature's `run.sh` also accepts the action directly if you'd rather
run it without going through `dispatch.sh` (e.g. from an existing
`/opt/vps-setup` checkout):

```bash
sudo bash argocd/run.sh down
sudo bash argocd/run.sh up # same as calling it with no argument
```

## Full copy-paste example

A realistic one-shot install on a fresh Ubuntu VPS, run as root right after
first boot. Replace the SSH key and auth key with your own (see
[Getting the keys you'll need](#getting-the-keys-youll-need) below):

```bash
curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/dispatch.sh -o /tmp/dispatch.sh

VPS_ADMIN_USER=ops \
    VPS_ADMIN_SSH_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... you@laptop" \
    TAILSCALE_AUTHKEY="tskey-auth-xxxxxxxxxxxx-xxxxxxxxxxxxxxxxxxxxxxxxxxxx" \
    RANCHER_HOSTNAME="rancher.tailnet-name.ts.net" \
    RANCHER_BOOTSTRAP_PASSWORD="$(openssl rand -base64 24)" \
    sh /tmp/dispatch.sh
```

This creates the `ops` sudo user with your key, disables SSH password
login, joins your tailnet immediately, and installs Cockpit + k3s +
Rancher. When it finishes, connect over Tailscale and open Cockpit
(`https://<tailscale-ip>:9080`) and Rancher
(`https://rancher.tailnet-name.ts.net:7083`) from a machine on the same
tailnet. Save the printed Rancher bootstrap password (also written to
`/root/.rancher-bootstrap-password`) to log in.

## Running from a non-standard branch or fork

The one-liner above always fetches `dispatch.sh` from `main`, but
`dispatch.sh` itself clones the whole repo again (into `VPS_SETUP_DIR`) to
get every feature folder - so to test a branch end-to-end you need to
point _both_ fetches at it with `VPS_SETUP_REPO_REF`.

> [!WARNING]
> **`export FOO=bar` then `... | sudo sh` will NOT work.** `sudo` resets
> the environment by default, so a plain shell `export` is invisible to the
> command it runs - `dispatch.sh` will silently fall back to `main` even
> though `echo $VPS_SETUP_REPO_REF` shows the right value in your shell.
> Either put the assignment directly on the `sudo` line (it is passed
> through even with env reset on), or use `sudo -E`. Don't do this:
>
> ```bash
> export VPS_SETUP_REPO_REF=my-branch # WRONG: lost by sudo
> curl -fsSL ".../my-branch/dispatch.sh" | sudo sh
> ```

Piped directly (no intermediate file), with the var set on the `sudo` line
so it survives:

```bash
BRANCH=claude/vps-setup-ubuntu-scripts-br4ddo

curl -fsSL "https://raw.githubusercontent.com/perspikapps/vps/${BRANCH}/dispatch.sh" \
    | sudo VPS_SETUP_REPO_REF="$BRANCH" bash
```

Or equivalently, keep your `export` but tell `sudo` to preserve it with `-E`
(only works if your sudoers config allows it - the explicit form above
always works and needs no special sudoers setup):

```bash
export VPS_SETUP_REPO_REF=claude/vps-setup-ubuntu-scripts-br4ddo
curl -fsSL "https://raw.githubusercontent.com/perspikapps/vps/${VPS_SETUP_REPO_REF}/dispatch.sh" \
    | sudo -E bash
```

Downloading to a file first (useful when passing several variables, as in
the [full example](#full-copy-paste-example) above) works the same way -
put every variable on the same line as `sudo`, before `bash`:

```bash
BRANCH=claude/vps-setup-ubuntu-scripts-br4ddo

curl -fsSL "https://raw.githubusercontent.com/perspikapps/vps/${BRANCH}/dispatch.sh" -o /tmp/dispatch.sh

sudo VPS_SETUP_REPO_REF="$BRANCH" \
    VPS_ADMIN_USER=ops VPS_ADMIN_SSH_KEY="ssh-ed25519 AAAA..." \
    sh /tmp/dispatch.sh
```

Env vars for this:

| Variable             | Default                                  | Purpose                             |
| -------------------- | ---------------------------------------- | ----------------------------------- |
| `VPS_SETUP_REPO_URL` | `https://github.com/perspikapps/vps.git` | Clone a fork instead                |
| `VPS_SETUP_REPO_REF` | `main`                                   | Branch, tag, or commit to check out |
| `VPS_SETUP_DIR`      | `/opt/vps-setup`                         | Where the repo is cloned/updated    |

To point at a fork as well as a branch, set both:

```bash
sudo VPS_SETUP_REPO_URL=https://github.com/ \
    VPS_SETUP_REPO_REF=my-feature \
    sh /tmp/dispatch.sh < you > /vps.git
```

`dispatch.sh` re-clones into `VPS_SETUP_DIR` on every run (`git fetch` +
`reset --hard` if it's already a checkout), so re-running it after pushing
new commits to the same branch picks them up automatically - no need to
re-download `dispatch.sh` itself unless you're switching branches/forks.

## Getting the keys you'll need

Every variable below can be set as an env var up front, but on an
interactive run (an actual terminal, not `curl | sudo sh`) you don't have
to: `dispatch.sh` prompts for whatever's still unset right before running
the enabled steps - see
[Interactive input prompts](#interactive-input-prompts-each-features-own-packagejson).

**SSH key pair** (for `VPS_ADMIN_SSH_KEY`) - generate one on your own
machine, never on the VPS:

```bash
ssh-keygen -t ed25519 -C "you@laptop" -f ~/.ssh/vps_ed25519
cat ~/.ssh/vps_ed25519.pub # paste this whole line as VPS_ADMIN_SSH_KEY
```

- If you already have a key, it's usually at `~/.ssh/id_ed25519.pub` or
  `~/.ssh/id_rsa.pub` (`cat` either one).
- GitHub/GitLab users already have a public key on file:
  `curl https://github.com/<your-username>.keys` returns it directly.
- Docs: [GitHub - Generating a new SSH key](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent),
  [Ubuntu - OpenSSH keys](https://ubuntu.com/server/docs/service-openssh).

**Tailscale auth key** (for `TAILSCALE_AUTHKEY`) - generate one in the
Tailscale admin console:

1. Go to <https://login.tailscale.com/admin/settings/keys>.
2. Click "Generate auth key". For a server, prefer a **reusable**,
   **ephemeral: off**, and **pre-approved** (if your tailnet requires
   device approval) key with a short expiry.
3. Copy the `tskey-auth-...` value into `TAILSCALE_AUTHKEY`.

Docs: [Tailscale - Auth keys](https://tailscale.com/kb/1085/auth-keys).
Without this variable, `vps-tailscale/run.sh` still installs Tailscale;
just run `tailscale up` manually afterwards and follow the login link.

**Rancher bootstrap password** (for `RANCHER_BOOTSTRAP_PASSWORD`) - any
string works; generate a random one with:

```bash
openssl rand -base64 24
```

If you don't set it, `rancher/run.sh` generates and saves one for
you automatically.

**GitHub App credentials** (for `GITHUB_ARC_APP_ID`,
`GITHUB_ARC_APP_INSTALLATION_ID`, `GITHUB_ARC_APP_PRIVATE_KEY_FILE`) -
create a GitHub App and install it on the org/repo you want runners for,
following
[the ARC quickstart](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/get-started#configuring-arc-with-a-github-app):

1. Create the App under your org/user settings, with the permissions the
   quickstart lists, then generate a private key for it (downloads a
   `.pem` file) and install it on the target org/repo.
2. Note the App ID (from the App's settings page) and the installation ID
   (from the URL after installing it: `.../installations/<ID>`).
3. Copy the downloaded `.pem` onto the VPS (e.g. `scp`) and point
   `GITHUB_ARC_APP_PRIVATE_KEY_FILE` at it - the key content itself is
   never passed as an env var.

## Provisioning via cloud-init / Kairos

[`cloud-init/kairos-vps-setup.yaml`](cloud-init/kairos-vps-setup.yaml) is a
`#cloud-config` user-data file that runs `dispatch.sh` unattended on first
boot - no interactive SSH session needed to kick it off. It works with:

- **[Kairos](https://kairos.io)** Ubuntu-flavored images, passed as the
  install config (e.g. `kairos-agent install --config
kairos-vps-setup.yaml`, or via the ISO/PXE/network install config).
- Any plain **cloud-init** VPS provider (DigitalOcean, Hetzner Cloud,
  OpenStack, etc.) that lets you paste "User data" at creation time -
  Kairos and stock cloud-init share the same document format for the
  `users` / `write_files` / `runcmd` keys this file uses.

To use it:

1. Copy the file and fill in the placeholders: your SSH public key (in two
   places - `users[].ssh_authorized_keys` and `VPS_ADMIN_SSH_KEY`), your
   Tailscale auth key, and `RANCHER_HOSTNAME`. See
   [Getting the keys you'll need](#getting-the-keys-youll-need) above.
2. Paste it into your provider's "User data" / cloud-init field (or pass it
   to Kairos) when creating the VPS.
3. On first boot the VPS installs itself unattended; check
   `/var/log/vps-setup.log` for progress/output.

Because `runcmd` already executes as root, this sidesteps the
[`export ... | sudo sh` env-var gotcha](#running-from-a-non-standard-branch-or-fork)
entirely - there's no `sudo` involved.

## Layout

- `dispatch.sh` - leading script, deliberately **plain POSIX `/bin/sh`**
  (see [One folder per feature](#one-folder-per-feature) for why): clones/
  updates this repo, ensures `jq` is installed on demand, discovers every
  `*/package.json`, resolves which steps run (flags, the
  [interactive menu](#interactive-menu), and
  [dependencies read straight from each package.json](#dependencies-between-steps)),
  bootstraps `zz_use` once via `setup.sh` (not per-feature - see below),
  and runs each feature's `run.sh` in order, idempotent and re-runnable,
  either `up` or [`down`](#removing-a-feature-updown-per-step).
- `summary/dispatch-steps.sh` - also plain POSIX `/bin/sh`, sourced by
  `dispatch.sh` once it knows its own repo root: the three per-step
  operations `dispatch.sh` drives on each feature - `state_get`/`state_set`
  (up/skip/down, per [Removing a feature](#removing-a-feature-updown-per-step)),
  `ask_missing_inputs` (see
  [Interactive input prompts](#interactive-input-prompts-each-features-own-packagejson)),
  and `run_step` (invokes `<name>/run.sh up|down` as a `bash`
  subprocess). Split out so the root script stays focused on flag parsing,
  the menu, and dependency resolution.
- `setup.sh` - installs `zz_use` (from
  [`tomgrv/scripts`](https://github.com/tomgrv/scripts)) onto `PATH`, then
  execs this repo's `"main"` entrypoint from `package.json` (`dispatch.sh`)
  if it's sitting next to `setup.sh` in a local checkout, forwarding every
  arg through - so `sh setup.sh --only-rancher` from an existing checkout
  works the same as calling `dispatch.sh` directly. Piped straight from
  `curl` with no local checkout (`curl .../setup.sh | sh -s -- ...`), there's
  no `package.json` next to the running script to find, so it only
  bootstraps `zz_use` and stops - use `dispatch.sh`'s own one-liner (which
  clones the repo first) for that case. A thin wrapper, deliberately:
  `zz_use` itself isn't this repo's script, so duplicating its own
  `setup.sh`'s bin-dir/linking logic here would just be a second copy to
  keep in sync. `dispatch.sh` runs it once, up front, itself falling back
  to `setup.sh` (and exec'ing back into itself) the same way if `zz_use`
  isn't on `PATH` yet; every feature's own `run.sh` no longer bootstraps
  `zz_use` itself (that would mean one `curl` per feature instead of one
  total) - it just fails fast with a one-line message pointing here if
  `zz_use` isn't already on `PATH` when run standalone. Pin the
  `tomgrv/scripts` ref with `ZZ_SCRIPTS_REF` (default `main`), or bootstrap
  from a fork entirely with `ZZ_SCRIPTS_SETUP_URL` (a full `setup.sh` URL).
  See
  [Replicating this pattern in another repo](#replicating-this-pattern-in-another-repo).
- `package.json` (root) - an npm **workspace** root (`"workspaces":
[<every top-level folder>]`); ties every feature package together for
  tooling (`npm install`, `npm ls`, lint-staged, commitlint's
  workspace-scope rules) without dispatch.sh itself needing npm/node at
  all.
- `cloud-init/kairos-vps-setup.yaml` - cloud-init/Kairos user-data that
  runs `dispatch.sh` unattended on first boot.
- `common/` - shared logging/retry/idempotency helpers sourced by every
  feature's `run.sh` (strict bash mode, non-interactive apt, "already
  done" checks); `net_port`/`net_access`/`all_network_ports` for reading
  each feature's own `package.json` port declarations - see
  [Network config](#network-config-each-features-own-packagejson); and
  `dispatch_action`/`helm_teardown`, the shared plumbing behind every
  feature's `up`/`down` actions. Colors and leveled logging
  (`log`/`ok`/`warn`/`die`) delegate to `zz_colors`/`zz_log` from
  [`tomgrv/scripts`](https://github.com/tomgrv/scripts) - the same core
  shared with `tomgrv/devcontainer-features`' common-utils feature -
  bootstrapped on first source via its `setup.sh` if not already on
  `PATH`. This is bash, not POSIX sh - every `run.sh` is invoked by
  `dispatch.sh` as a `bash` subprocess, never sourced from the sh
  dispatcher itself. Like every feature, `common/` is a top-level
  `<name>/{package.json,run.sh}` folder in this repo, laid out the same
  way [`tomgrv/scripts`](https://github.com/tomgrv/scripts) lays out its
  own scripts - which is what lets `zz_use` fetch and install it (or any
  feature) directly from this repo, from anywhere:
  `zz_use perspikapps/vps/common`. It isn't an installable step itself,
  though - `dispatch.sh`'s feature discovery skips it (and `summary/`)
  explicitly.
- `summary/` - prints connection info, the Tailscale URL, and the
  Cockpit/Rancher/ArgoCD/Epinio credentials at the end of a run. Also its
  own top-level `zz_use`-installable folder, also excluded from feature
  discovery.
- `system/` - apt update/upgrade, base tooling, unattended
  security upgrades.
- `security/` - optional non-root admin user, ufw
  (default-deny inbound, rules generated from every feature's own
  `package.json` port declarations: SSH and Traefik's 80/443 public,
  everything else Tailscale-only), sshd hardening, fail2ban, and a
  Cockpit/console login password.
- `vps-tailscale/` - installs Tailscale, enables `tailscaled` as a
  systemd service, and joins the tailnet.
- `cockpit/` - installs Cockpit, served on ports 9080/9083.
- `k3s/` - installs k3s (Traefik enabled), kubectl, Helm, and
  configures Traefik as a public HTTP/HTTPS ingress with a Let's Encrypt
  certResolver and a Tailscale-only dashboard - see
  [Traefik ingress](#traefik-ingress-lets-encrypt-and-the-dashboard).
- `rancher/` - installs cert-manager (required by Rancher's
  self-signed TLS even with ingress disabled) and the latest Rancher via
  Helm, exposed on ports 7080/7083 through k3s's built-in ServiceLB.
  Depends on `k3s` (see its `package.json`).
- `dockermanager/` - installs `cockpit-packagekit`,
  `cockpit-files`, Docker (`docker.io`, as a dependency), and the
  third-party [cockpit-dockermanager](https://github.com/chrisjbawden/cockpit-dockermanager)
  plugin for managing Docker containers/images from Cockpit.
- `argocd/` - installs ArgoCD via Helm for GitOps-managed
  deployments onto the k3s cluster, exposed on ports 7090/7093 through
  k3s's built-in ServiceLB. Opt-in; depends on `k3s`.
- `epinio/` - installs [Epinio](https://epinio.io) via Helm
  for deploying apps straight from source, routed through Traefik's
  existing ingress rather than a dedicated port - see
  [Epinio (deploy apps from source)](#epinio-deploy-apps-from-source).
  Opt-in; depends on `k3s`.
- `github-arc/` - installs GitHub Actions Runner Controller
  (ARC) via Helm, registering self-hosted runners against a GitHub org
  or repo - see
  [GitHub Actions Runner Controller (ARC)](#github-actions-runner-controller-arc).
  Opt-in; depends on `k3s`.

## One folder per feature

Each feature is a small, self-contained npm workspace package:

```
rancher/
  package.json   # name, description, "bin": { "rancher": "run.sh" },
                 # "vps": { "default": true|false }, and
                 # "dependencies": { "@tomgrv/vps-<other-feature>": "*" }
  run.sh         # up() and down() - see Removing a feature, below
```

Folder names carry no ordering (`rancher/`, not
`05-rancher/`) - install order is a plain integer,
`package.json`'s `vps.order`, and `dispatch.sh` sorts by that instead of
by folder name. Everything that used to live in `setup.sh`'s
hand-maintained bash tables (label, install order, default on/off, what
depends on what) now lives in each feature's own `package.json`, under
`vps`:

```json
{
    "name": "@tomgrv/vps-rancher",
    "version": "1.0.0",
    "private": true,
    "description": "Rancher install",
    "bin": { "rancher": "run.sh" },
    "vps": { "order": 5, "default": true },
    "dependencies": { "@tomgrv/vps-k3s": "*", "@tomgrv/vps-common": "*" }
}
```

`"bin"` follows the same `{"<name>": "run.sh"}` convention
[`tomgrv/scripts`](https://github.com/tomgrv/scripts) uses for its own
scripts - what makes `zz_use perspikapps/vps/rancher` resolvable (see
[Running a single feature via `zz_use`](#running-a-single-feature-via-zz_use-without-this-repo-at-all)
below). `"dependencies"` always includes `@tomgrv/vps-common` (every feature
sources it - see [Layout](#layout)), plus any other `@tomgrv/vps-<feature>` it
needs; `dispatch.sh`'s own dependency reading (auto-enable,
`--down-<step>` refusal) explicitly excludes `common`/`summary` from this
field, since neither is an installable step.

One folder is named differently from its own feature for exactly this
reason: `vps-tailscale/`, not `tailscale/` - its `run.sh` calls the real
`tailscale` CLI internally, and `zz_use` has no notion of `"bin"` at all
(it always installs `<name>/run.sh` under the literal folder name `<name>`
it was asked for) - `zz_use perspikapps/vps/tailscale` would install this
feature's own script as `tailscale`, shadowing the actual binary it
depends on. Its `package.json`'s `"name"` field is still `"@tomgrv/vps-tailscale"`
though (that's what `dispatch.sh` reads - CLI flags like `--only-tailscale`
are unaffected), so only the folder (and therefore the `zz_use`/`"bin"`
identity) differs from every other feature's own name.

Adding a new feature is: create `whatever/` with a
`package.json` (following the shape above, with an `order` that places it
where you want in the install sequence) and a `run.sh` (`up()`/`down()` +
`dispatch_action "$@"` at the end, same as any other feature - see
`common/`). `dispatch.sh` picks it up automatically; add it to root
`package.json`'s `"workspaces"` array too. Removing a feature is deleting
its folder (and that array entry).

The root `package.json`'s `"workspaces"` array registers every
feature as an npm workspace member, so standard npm tooling (`npm ls`,
`npm install`, the repo's existing lint-staged/commitlint config, which
already referenced `@commitlint/config-workspace-scopes`) understands the
dependency graph too - `package-lock.json` resolves `@tomgrv/vps-rancher`'s
`@tomgrv/vps-k3s` dependency like any other workspace package. `dispatch.sh`
itself never needs npm installed, though: it's plain POSIX `/bin/sh` (see
[Layout](#layout)) and reads each `package.json`'s `dependencies`/`vps`
fields with `jq` - installed on demand (`ensure_jq`) if missing, since
this runs before `system` (the step that would otherwise install
it) on a totally fresh box.

### Running a single feature via `zz_use`, without this repo at all

Because every feature is a top-level `<name>/run.sh` folder - the same
layout [`tomgrv/scripts`](https://github.com/tomgrv/scripts) uses for its
own scripts - `zz_use` (from that repo) can fetch and install any one of
them directly, from any machine, without cloning this repo or running
`dispatch.sh`:

```sh
curl -fsSL https://raw.githubusercontent.com/tomgrv/scripts/main/setup.sh | sh
command -v jq > /dev/null || sudo apt-get update && sudo apt-get install -y jq # common/run.sh needs it
zz_use perspikapps/vps/rancher
sudo rancher up
```

`zz_use`'s `[org/repo/]<tool>[@ref]` syntax resolves `perspikapps/vps` as
the origin and `rancher` as the script, downloads this repo (cached
locally after the first call, per-origin/ref - see
[`tomgrv/scripts`'s README](https://github.com/tomgrv/scripts#caching-zz_update-and-pinning-an-originref)),
and symlinks `rancher/run.sh` onto `PATH` as `rancher`. Since every
feature's own `run.sh` in turn fetches `common/run.sh` from this same
repo the same way, a feature installed this way works exactly like it
would through `dispatch.sh` - it just skips discovery, ordering,
dependency auto-enable, and the interactive menu, so you're responsible
for running any features it depends on yourself first (see
[Dependencies between steps](#dependencies-between-steps)).

## Network config (each feature's own `package.json`)

Every port this repo opens, and whether it's public or Tailscale-only, is
declared on the feature that owns it, in its `package.json`'s `vps.ports`
array (same file that carries `vps.default`/`dependencies` - see
[One folder per feature](#one-folder-per-feature)). Each entry looks like:

```json
{
    "name": "rancher_http",
    "port": 7080,
    "access": "tailscale",
    "note": "optional, becomes the ufw rule's comment"
}
```

(`access` is `"tailscale"` or `"public"`.) `rancher/package.json`
carries `rancher_http`/`rancher_https`, `k3s/package.json`
carries `http`/`https`/`traefik_dashboard`, and so on - each feature's own
`run.sh` is what actually binds the port, so its declaration lives right
next to the code that uses it instead of a separate central file.

`security/run.sh` doesn't know about any of that port detail
itself: it calls `common/run.sh`'s `all_network_ports()`, which scans
every `*/package.json` and builds ufw's rules from whatever it
finds - there's no per-service ufw logic in that script at all, just a
loop over that combined list. Every feature that binds a port itself
(Cockpit, Rancher, Traefik's dashboard, ArgoCD) reads its own default via
`common/run.sh`'s `net_port()` helper (resolving its _own_ package.json
automatically - see the function's comment for how `summary/run.sh`, which
isn't any one feature, asks for another feature's port explicitly), so the
port ufw opens and the port the app actually listens on can't drift apart.

To change a default port for good, edit that feature's `package.json` and
re-run the affected step(s) (e.g. `--only-security --only-rancher` after
changing `rancher_http`). To override a port for a single run without
editing anything, use its env var - the name is always the entry's `name`,
upper-cased, with `_PORT` appended: `rancher_http` -> `RANCHER_HTTP_PORT`,
`ssh` -> `SSH_PORT`, and so on.

Lookups are done with `jq` (see [Layout](#layout)'s `ensure_jq`) - no
separate YAML tooling needed now that this lives in `package.json`
alongside everything else npm already parses.

## Interactive input prompts (each feature's own `package.json`)

Every feature's `package.json` also declares `vps.inputs` and
`vps.outputs`, in the same shape as a
[GitHub composite action's `inputs:`/`outputs:`](https://docs.github.com/en/actions/sharing-automations/creating-actions/metadata-syntax-for-github-actions#inputs)

- except each input's key IS the env var its own `run.sh` reads (no
  separate id-to-env-var mapping to keep in sync):

```json
"vps": {
    "inputs": {
        "TAILSCALE_AUTHKEY": {
            "description": "Auth key to auto-join a tailnet",
            "required": true,
            "default": ""
        }
    },
    "outputs": {
        "TAILSCALE_IP": {
            "description": "Tailnet IPv4 address once joined"
        }
    }
}
```

Before running any enabled step, `dispatch.sh` walks every "up" step's
`vps.inputs` and, for each one not already set in the environment, prompts
for it on stdin - showing its `description` and `default` (empty **Enter**
accepts the default, or leaves an optional var unset). This only happens
on an actual terminal (`[ -t 0 ]`): the piped one-liner
(`curl ... | sudo sh`) has nothing to read prompts from, so there env
vars (or `--skip-<step>`) remain the only way to supply them, exactly as
before this existed. A var already set beforehand (env var, or exported
by an earlier prompt) is never re-asked.

```
==== Feature inputs ====
  TAILSCALE_AUTHKEY (Auth key to auto-join a tailnet) (required): tskey-...
  TAILSCALE_EXTRA_ARGS (Extra flags appended to tailscale up) [optional, enter to skip]:
  RANCHER_HTTP_PORT (Rancher HTTP port) [7080]:
```

This runs early enough that answering the prompt for a required var (like
`TAILSCALE_AUTHKEY` above) also satisfies the dedicated
[tailscale guard](#security-model) further down - you're not asked twice.
`vps.outputs` is documentation only (what a feature produces and, where
meaningful, where it's saved - e.g. `/root/.rancher-bootstrap-password`);
nothing currently reads it back programmatically.

Adding a new input to a feature is a `package.json` edit plus reading the
matching env var in that feature's `run.sh` - no change to `dispatch.sh`
itself (its `pkg_input_*` helpers read `vps.inputs` generically via
`jq`).

## Security model

SSH and HTTP/HTTPS (Traefik's ingress) are the only things reachable from
the public internet. Everything else - Cockpit, Rancher, the Traefik
dashboard, ArgoCD, the k3s API - is bound by `ufw` to the `tailscale0`
interface only, so you must join the same tailnet to reach them. Epinio
is the one exception: it isn't bound to a port `ufw` can gate, since it's
ingress-routed on the same public 80/443 as Traefik itself - see
[Epinio (deploy apps from source)](#epinio-deploy-apps-from-source).

HTTP/HTTPS are public unconditionally, not behind a flag: Traefik is this
VPS's real ingress, and Let's Encrypt's HTTP-01 challenge needs port 80
reachable from the internet to issue certs at all - a Tailscale-only
ingress would defeat the point of having one.

Because of this, **`dispatch.sh` refuses to run at all if the Tailscale step
is enabled but `TAILSCALE_AUTHKEY` is unset** - proceeding anyway would
lock down ufw and leave every Tailscale-only service unreachable by
anything. Pass `--skip-tailscale` if you genuinely want to run without
Tailscale (you can join manually later with `tailscale up`, then `sudo
sh dispatch.sh --only-tailscale`).

## Traefik ingress: Let's Encrypt and the dashboard

`k3s/run.sh` leaves k3s's bundled Traefik enabled (rather than
disabling it, as you'll see suggested in some k3s+Rancher guides) and
configures it as this VPS's public ingress via a `HelmChartConfig` -
k3s's own mechanism for overriding a bundled chart's values, watched
continuously so it's safe to re-apply any time (e.g. via `--only-k3s`).

- **Public HTTP/HTTPS, any hostname**: ports 80/443 are k3s's own defaults
  for Traefik's `web`/`websecure` entrypoints, exposed via its built-in
  ServiceLB like Rancher's ports - no extra configuration needed, just
  ufw open on those two (see [Security model](#security-model)). Traefik
  routes by the incoming request's `Host` header, not a fixed hostname
  list: any FQDN or subdomain you point at this VPS's public IP is routed
  by whichever `Ingress` declares that host, with no changes needed here
    - that's how Epinio's per-app subdomains work too (see
      [Epinio](#epinio-deploy-apps-from-source)).
- **Let's Encrypt**: a certResolver named `letsencrypt` is configured
  (email from `TRAEFIK_ACME_EMAIL`, HTTP-01 challenge on the `web`
  entrypoint, state persisted to a PVC so certs survive pod restarts).
  This makes the resolver _available_ - it doesn't issue anything by
  itself. To get a real cert for your own app, create an `Ingress` (or
  Traefik `IngressRoute`) with the annotation
  `traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt`,
  and a real DNS record pointing this VPS's public IP at your hostname
  (the HTTP-01 challenge needs that to succeed). Each hostname gets its
  own cert, issued on demand the first time it's requested - HTTP-01
  can't issue a single wildcard cert covering a domain and all its
  subdomains at once (that needs a DNS-01 challenge, which isn't wired up
  here); every Ingress you add gets its own cert instead.
- **Staging by default**: `TRAEFIK_ACME_STAGING` defaults to `true`, which
  points the resolver at Let's Encrypt's _staging_ environment - browsers
  will show a certificate-warning page, but there's no rate limit, so
  it's safe to test against repeatedly while you get your Ingress/DNS
  right. Set `TRAEFIK_ACME_STAGING=false` once you're ready for real,
  trusted certs (production Let's Encrypt has strict per-domain rate
  limits - avoid iterating against it directly).
- **Dashboard**: exposed on `TRAEFIK_DASHBOARD_PORT` (default `8088`),
  Tailscale-only like Cockpit/Rancher, at `http://<tailscale-ip>:8088/dashboard/`
  (trailing slash required). It has no login of its own - that's fine
  given it's already gated to the tailnet, same threat model as the rest
  of this repo's admin surfaces, but don't put it on a public port.

## Cockpit, Rancher, and ArgoCD logins

- **Cockpit** authenticates via PAM against a real Linux account and
  password - separate from SSH, which stays key-only. `security/run.sh`
  sets a password for `VPS_ADMIN_USER` (or `root` if that's unset): either
  `VPS_ADMIN_PASSWORD` if you set it, or a random one saved to
  `/root/.cockpit-admin-password` (username in `/root/.cockpit-admin-user`).
- **Rancher** username is always `admin`; the initial password is
  `RANCHER_BOOTSTRAP_PASSWORD` if set, otherwise a random one saved to
  `/root/.rancher-bootstrap-password`. Rancher prompts you to change it on
  first login.
- **ArgoCD** username is always `admin`; the auto-generated initial
  password is saved to `/root/.argocd-admin-password`. It's deleted from
  the cluster (the `argocd-initial-admin-secret`) the first time you
  change it in the UI/CLI, but the file this repo saved keeps working as
  a record of what it originally was.

## ArgoCD (GitOps deployments)

Opt-in - pass `--with-argocd` (or `--only-argocd`) to install it; it
doesn't run on a plain `dispatch.sh` with no flags.

`argocd/run.sh` installs [ArgoCD](https://argo-cd.readthedocs.io/)
via the `argo/argo-cd` Helm chart onto the k3s cluster from `k3s`,
a natural pairing with Rancher for cluster management (see
[this write-up](https://oneuptime.com/blog/post/2026-03-20-rancher-argocd/view)
on running the two together). It's exposed on `ARGOCD_HTTP_PORT`/
`ARGOCD_HTTPS_PORT` (default `7090`/`7093`) through k3s's built-in
ServiceLB, Tailscale-only like Cockpit and Rancher. The server runs with
TLS termination left to you (`server.insecure=true` in the chart, i.e.
ArgoCD serves plain HTTP on its own port rather than trying to manage
its own cert) since it isn't sitting behind the Traefik ingress.

The `dex` (SSO) and notifications controller components are disabled
(`dex.enabled=false`, `notifications.enabled=false`) since this repo only
uses ArgoCD's built-in admin login - fewer pods means less to pull images
for and wait on, which matters on a small single-node VPS. If a first
install still doesn't finish within the default 15 minutes (a slow first
image pull is the usual cause - check `kubectl -n argocd get pods` for
`Pending`/`ImagePullBackOff`), either just re-run `sudo sh dispatch.sh
--only-argocd` (helm resumes the same release without re-pulling cached
images), or set `ARGOCD_INSTALL_TIMEOUT` to a larger value first.

Point ArgoCD at your Git repos and `Application` manifests the usual way
(`argocd repo add`, `argocd app create`, or the UI) once you've logged in

- see the [ArgoCD docs](https://argo-cd.readthedocs.io/en/stable/getting_started/)
  for that workflow; this repo only handles getting ArgoCD itself installed
  and reachable.

Both credentials, along with the Tailscale IP/URL to reach them on, are
printed by `summary/run.sh` at the end of the install (and any time
you re-run it: `sudo bash /opt/vps-setup/summary/run.sh`).

## Epinio (deploy apps from source)

Opt-in - pass `--with-epinio` (or `--only-epinio`) to install it; it
doesn't run on a plain `dispatch.sh` with no flags.

`epinio/run.sh` installs [Epinio](https://epinio.io) - "from app to
URL in one command" - via the official `epinio/epinio` Helm chart, per
[the getting-started guide](https://docs.epinio.io/getting-started/install-epinio)
(mirrored here from [the chart repo's own README](https://github.com/epinio/helm-charts),
since `docs.epinio.io` wasn't reachable while writing this script - if
anything here drifts from the live docs, that's the site to check). It
reuses this VPS's existing infrastructure rather than installing its own
copies: k3s's bundled Traefik as its ingress controller, explicitly
pinned via `EPINIO_INGRESS_CLASS` (default `traefik`) on all three of the
chart's ingress-class settings (its own server, deployed apps, and its
internal container registry) rather than relying on Traefik just
happening to be k3s's default IngressClass; and cert-manager, installed
only if not already present - the same idempotent check
`rancher/run.sh` uses, so it reuses Rancher's cert-manager if that
step ran, or installs its own if you skipped Rancher.

Unlike Cockpit/Rancher/ArgoCD, Epinio doesn't get a dedicated port: it
creates its own Ingresses (`epinio.<domain>`, `auth.<domain>`, and one per
app you deploy) on Traefik's existing public 80/443, the same way any
app you `epinio push` will be. That means Epinio's dashboard is reachable
from the public internet once its domain resolves - gated by its own
login, not by `ufw` (see [Security model](#security-model)).

- **Domain**: Epinio requires a wildcard DNS domain pointed at this VPS's
  public IP (`EPINIO_DOMAIN`). Without one, it defaults to
  [sslip.io](https://sslip.io) magic DNS (`<node-ip>.sslip.io`, which
  resolves any subdomain back to that IP) - fine for trying Epinio out,
  not something to depend on. Set `EPINIO_DOMAIN` to a real domain you
  control before deploying anything you care about.
- **TLS**: certs come from cert-manager via `EPINIO_TLS_ISSUER` (default
  `epinio-ca`, a self-signed CA Epinio creates itself - browsers will
  warn). Epinio also ships `letsencrypt-staging`/`letsencrypt-production`
  ClusterIssuers if you'd rather use those once `EPINIO_DOMAIN` is real.
- **Login**: username `admin`, password `EPINIO_ADMIN_PASSWORD` if set,
  otherwise a random one saved to `/root/.epinio-admin-password`.
- **CLI**: the `epinio` binary is installed to `/usr/local/bin/epinio`.
  Log in with `epinio login -u admin -p '<password>' https://epinio.<domain>`,
  then deploy an app from a source directory with `epinio push`.
- This chart also deploys SeaweedFS (S3-compatible storage for source
  blobs), its own container registry, and Dex, on top of Epinio itself -
  more images to pull than Rancher or ArgoCD, so a slow first install is
  normal. If it doesn't finish within the default `EPINIO_INSTALL_TIMEOUT`
  (15 minutes), check `kubectl -n epinio get pods` for
  `Pending`/`ImagePullBackOff`, then just re-run `sudo sh dispatch.sh
--only-epinio` (helm resumes the same release without re-pulling cached
  images), or set `EPINIO_INSTALL_TIMEOUT` higher first.

The login and dashboard URL are printed by `summary/run.sh` like
every other step's credentials.

## GitHub Actions Runner Controller (ARC)

Opt-in - pass `--with-github-arc` (or `--only-github-arc`) to install it;
it doesn't run on a plain `dispatch.sh` with no flags.

`github-arc/run.sh` installs
[GitHub Actions Runner Controller](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/get-started)
(ARC) via its two official Helm charts - the controller
(`gha-runner-scale-set-controller`) and a runner scale set
(`gha-runner-scale-set`) - both into a single `github` namespace on the
k3s cluster, so self-hosted GitHub Actions runners can be dispatched
straight onto this VPS.

Authentication is via a GitHub App, the method the docs recommend over a
personal access token - you create the App yourself (following the
quickstart above) and give this script its credentials; it doesn't create
the App for you.

- **Required**: `GITHUB_ARC_CONFIG_URL` (the org or repo the runners
  register against, e.g. `https://github.com/perspikapps` or
  `https://github.com/perspikapps/vps`), `GITHUB_ARC_APP_ID`,
  `GITHUB_ARC_APP_INSTALLATION_ID`, and
  `GITHUB_ARC_APP_PRIVATE_KEY_FILE` (a path to the App's private key PEM
    - not the key content itself, so it's never passed on the command line
      or logged).
- **Scaling**: `GITHUB_ARC_MIN_RUNNERS`/`GITHUB_ARC_MAX_RUNNERS` (default
  `0`/`5`) control the runner scale set's autoscaling range.
- Neither chart binds a port `ufw` needs to know about: runners connect
  outbound to GitHub, nothing needs to be reachable from outside the
  cluster.

```bash
sudo GITHUB_ARC_CONFIG_URL=https://github.com/perspikapps/vps \
    GITHUB_ARC_APP_ID=123456 \
    GITHUB_ARC_APP_INSTALLATION_ID=78901234 \
    GITHUB_ARC_APP_PRIVATE_KEY_FILE=/root/github-arc-app.private-key.pem \
    sh dispatch.sh --only-github-arc
```

Check on it with `kubectl -n github get autoscalingrunnersets` and
`kubectl -n github get pods`; `summary/run.sh` reports whether it's
installed like every other step.

## Key environment variables

All `*_PORT` variables below are per-run overrides of a default that
actually lives in the owning feature's own `package.json` - see
[Network config](#network-config-each-features-own-packagejson) - edit
that file to change a default for good, or set the env var for one run.

| Variable                                            | Default              | Purpose                                                                                                          |
| --------------------------------------------------- | -------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `VPS_ADMIN_USER`                                    | unset                | Create this sudo user                                                                                            |
| `VPS_ADMIN_SSH_KEY`                                 | unset                | Authorized key for the admin user and root                                                                       |
| `VPS_ADMIN_PASSWORD`                                | random               | Cockpit/console login password (separate from SSH)                                                               |
| `SSH_PORT`                                          | `22`                 | SSH port kept open publicly                                                                                      |
| `TAILSCALE_AUTHKEY`                                 | unset                | Auto-join a tailnet (**required** unless `--skip-tailscale`)                                                     |
| `TAILSCALE_EXTRA_ARGS`                              | unset                | Extra flags appended to `tailscale up`                                                                           |
| `COCKPIT_HTTP_PORT` / `COCKPIT_HTTPS_PORT`          | `9080` / `9083`      | Cockpit ports (`9xxx`)                                                                                           |
| `RANCHER_HTTP_PORT` / `RANCHER_HTTPS_PORT`          | `7080` / `7083`      | Rancher ports (`7xxx`)                                                                                           |
| `RANCHER_HOSTNAME`                                  | node IP              | Hostname used in Rancher's cert                                                                                  |
| `RANCHER_BOOTSTRAP_PASSWORD`                        | random               | Rancher initial admin password                                                                                   |
| `INSTALL_DOCKER`                                    | `true`               | Install `docker.io` for cockpit-dockermanager to manage                                                          |
| `COCKPIT_DOCKERMANAGER_VERSION`                     | `latest`             | [cockpit-dockermanager](https://github.com/chrisjbawden/cockpit-dockermanager) release tag to install            |
| `TRAEFIK_ACME_EMAIL`                                | placeholder          | Let's Encrypt contact email - set this to a real address                                                         |
| `TRAEFIK_ACME_STAGING`                              | `true`               | Use Let's Encrypt's staging (untrusted, no rate limit) vs. production certs                                      |
| `TRAEFIK_DASHBOARD_PORT`                            | `8088`               | Traefik dashboard port (Tailscale-only)                                                                          |
| `ARGOCD_HTTP_PORT` / `ARGOCD_HTTPS_PORT`            | `7090` / `7093`      | ArgoCD ports (`7xxx`, alongside Rancher)                                                                         |
| `ARGOCD_CHART_VERSION`                              | latest               | Pin the `argo/argo-cd` Helm chart version                                                                        |
| `ARGOCD_INSTALL_TIMEOUT`                            | `15m`                | How long to wait for ArgoCD's pods to come up                                                                    |
| `EPINIO_DOMAIN`                                     | `<node-ip>.sslip.io` | Wildcard domain Epinio's Ingresses use - set to a real domain                                                    |
| `EPINIO_INGRESS_CLASS`                              | `traefik`            | IngressClass Epinio's Ingresses are pinned to (reuses k3s's bundled Traefik)                                     |
| `EPINIO_TLS_ISSUER`                                 | `epinio-ca`          | cert-manager ClusterIssuer: `epinio-ca`, `selfsigned-issuer`, `letsencrypt-staging`, or `letsencrypt-production` |
| `EPINIO_ADMIN_PASSWORD`                             | random               | Epinio admin login password                                                                                      |
| `EPINIO_CHART_VERSION`                              | latest               | Pin the `epinio/epinio` Helm chart version                                                                       |
| `EPINIO_INSTALL_TIMEOUT`                            | `15m`                | How long to wait for Epinio's pods to come up                                                                    |
| `CERT_MANAGER_VERSION`                              | latest               | Pin cert-manager's chart version (shared by Rancher and Epinio)                                                  |
| `GITHUB_ARC_CONFIG_URL`                             | unset                | Org or repo URL runners register against (**required**)                                                          |
| `GITHUB_ARC_APP_ID`                                 | unset                | GitHub App ID (**required**)                                                                                     |
| `GITHUB_ARC_APP_INSTALLATION_ID`                    | unset                | GitHub App installation ID (**required**)                                                                        |
| `GITHUB_ARC_APP_PRIVATE_KEY_FILE`                   | unset                | Path to the GitHub App's private key PEM (**required**)                                                          |
| `GITHUB_ARC_RUNNER_SCALE_SET_NAME`                  | `arc-runner-set`     | Name of the runner scale set                                                                                     |
| `GITHUB_ARC_MIN_RUNNERS` / `GITHUB_ARC_MAX_RUNNERS` | `0` / `5`            | Runner scale set autoscaling range                                                                               |
| `GITHUB_ARC_CONTROLLER_CHART_VERSION`               | latest               | Pin the `gha-runner-scale-set-controller` chart version                                                          |
| `GITHUB_ARC_RUNNER_SET_CHART_VERSION`               | latest               | Pin the `gha-runner-scale-set` chart version                                                                     |
| `GITHUB_ARC_INSTALL_TIMEOUT`                        | `10m`                | How long to wait for each Helm install                                                                           |

Ports follow a per-app range so they're easy to tell apart at a glance:
Cockpit `9xxx`, Rancher and ArgoCD `7xxx`, Traefik dashboard `8xxx` - the
ingress itself is always 80/443, per HTTP/HTTPS convention, not part of
this scheme.

Each feature's `run.sh` can also be run standalone, from within a
checkout or on its own - but it doesn't bootstrap `zz_use` itself (that's
`setup.sh`'s job, run once - see [Layout](#layout)); it just fetches
`common/run.sh` from this repo via `zz_use perspikapps/vps/common` if
`zz_use` is already on `PATH`, and fails fast with a one-line message
pointing at `setup.sh` if it isn't:

```sh
curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/setup.sh | sh
sudo RANCHER_HOSTNAME=new.example.com bash rancher/run.sh
```

This is what `dispatch.sh --only-<step>`, described in
[Running a single step (or a subset)](#running-a-single-step-or-a-subset)
above, does for you (and bootstraps `zz_use` for, once, up front, for
every step - not per-feature).

Every `run.sh` also takes an explicit `up` or `down` action as its first
argument (`up` is the default, so the invocation above is really `...
bash rancher/run.sh up`) - see
[Removing a feature](#removing-a-feature-updown-per-step) for what each
step's `down` does.

## Troubleshooting: a step fails or "just stops"

Every script runs under `set -euo pipefail` and sources `common/run.sh`,
which installs an error trap: the first command that fails without being
explicitly handled (i.e. not part of an `if`/`&&`/`||`) prints its exact
file, line number, and the failing command, then the script exits. For
example:

```
[vps-setup] ERROR: command failed (exit 1) at /opt/vps-setup/rancher/run.sh line 52: helm upgrade --install rancher ...
```

When a step fails during a full `dispatch.sh` run, it also prints which
numbered step failed and how to re-run just that one after fixing the
issue:

```
[vps-setup] Step 'Rancher install' (rancher/run.sh up) failed (exit 1) - see the error above. Fix it and re-run just this step with: sudo sh dispatch.sh --only-rancher
```

If you ever see a step stop with truly no output at all (not even its own
first `log` line), that most often means a _prerequisite_ step was
skipped - e.g. running `--only-rancher` on a box where `--only-k3s` (or a
full run) was never done first, so `kubectl`/`helm` don't exist yet.
`rancher/run.sh`, `argocd/run.sh`, and `epinio/run.sh`
all check for `kubectl`/`helm` explicitly and `die` with a clear message
in that case; if you hit a silent stop anywhere else, please open an
issue with the exact command you ran and the last few lines of output.

## Tests

```sh
npm install --global bats # or: apt-get install bats
curl -fsSL https://raw.githubusercontent.com/tomgrv/scripts/main/setup.sh | sh
bats tests/
```

Covers script syntax (`sh -n`/`bash -n` on every `run.sh`/`dispatch.sh`),
the `zz_use`/`common` wiring every `run.sh` is expected to have, and
`common/run.sh`'s pure logic (`net_port`, `net_access`,
`all_network_ports`, `feature_package_json`, `dispatch_action`) against a
small fixture tree. The features themselves (apt/Helm/k3s installs) need
a live root Ubuntu box to actually test, so that part of this repo has no
automated coverage.

## Releasing

GitHub → Actions → `release-main` → "Run workflow" — a `workflow_dispatch`
button in the web UI, no `gh`/`git` CLI needed. It calls
[`tomgrv/actions`](https://github.com/tomgrv/actions)'s shared
`release-promote` composite action, which pulls
`git-release-beta`/`git-release-prod` from
[`tomgrv/scripts`](https://github.com/tomgrv/scripts#git-utilities) and
runs them non-interactively. The `.vscode/tasks.json` "🎈 Beta"/"🚀 Prod"
tasks that used to run the same commands locally have been retired in
favor of this — `git-flow`/`gitutils` still need to be installed locally
for the "🚑 Hotfix" task and everyday `git align`/`git amend`/etc.
shortcuts, just not for cutting a release anymore. See
[`tomgrv/actions`'s release-process doc](https://github.com/tomgrv/actions/blob/main/docs/release-process.md)
for the tag/branch-protection bypass this repo's `main` needs for the
workflow's final push to succeed.

## Replicating this pattern in another repo

This repo, [`tomgrv/devcontainer-features`](https://github.com/tomgrv/devcontainer-features)'
`common-utils` feature, and [`tomgrv/scripts`](https://github.com/tomgrv/scripts)
itself all share the same shape - a repo that's both a normal codebase
and a `zz_use`-installable source of scripts. Adopting it elsewhere:

1. **One top-level folder per script**, each an npm workspace package:
   `<name>/package.json` + `<name>/run.sh` (+ optionally `README.md`,
   `test.bats`, `config/`). This is the one hard requirement -
   `zz_use org/repo/<name>` only works if `<name>/run.sh` sits directly
   under the repo root. `package.json` needs at minimum a `"name"` and
   `"bin": {"<name>": "run.sh"}` (the latter is for `npm`/workspace
   tooling only - `zz_use` itself always installs under the literal
   folder name requested, never reads `"bin"` - see
   [One folder per feature](#one-folder-per-feature) above for why that
   distinction matters, e.g. `vps-tailscale/`).
2. **A root `setup.sh`** that installs `zz_use` (from
   [`tomgrv/scripts`](https://github.com/tomgrv/scripts)) onto `PATH`, then
   execs your `package.json`'s `"main"` field (falling back to a root
   `main.sh`, or just stopping if neither exists) - copy this repo's
   `setup.sh` verbatim; it doesn't hardcode `perspikapps/vps` anywhere, it
   only needs the `tomgrv/scripts` URL and a `"main"`/`main.sh` next to
   itself. Your dispatcher (this repo's `dispatch.sh`, or whatever entry
   point runs every script in sequence) is that `"main"` target, and runs
   `setup.sh` **once**, up front, forwarding its own args back into itself
   on the way out:
    ```sh
    command -v zz_use > /dev/null 2>&1 || exec sh "$REPO_ROOT/setup.sh" "$@"
    ```
    Individual scripts don't bootstrap `zz_use` themselves - that would
    mean one `curl` per script instead of one total, exactly the
    duplication a root `setup.sh` exists to avoid. They just fail fast if
    it's somehow still missing (e.g. run standalone, outside the
    dispatcher):
    ```sh
    command -v zz_use > /dev/null 2>&1 || {
        echo "zz_use not found on PATH - run this repo's setup.sh first: curl -fsSL https://raw.githubusercontent.com/<org>/<repo>/main/setup.sh | sh" >&2
        exit 1
    }
    ```
    Never embed the `tomgrv/scripts` URL directly in more than one place.
3. **A shared `common/` folder** (or whatever you'd call it) for logic
   more than one script needs - not a "core" script itself, just another
   `<name>/run.sh` folder, sourced via
   `zz_use <org>/<repo>/common; . common` rather than a relative
   `source ../lib/common.sh`, so it resolves the same way whether a
   script runs from a local checkout, standalone, or `zz_use`-installed
   from anywhere. Exclude it (and anything else that's shared logic
   rather than an installable unit, like this repo's `summary/`) from
   whatever discovers your installable units by convention - see
   `dispatch.sh`'s `list_feature_dirs()`/`feature_deps()` here for how
   this repo does it.
4. **Root `package.json`**: an npm workspaces root listing every folder
   explicitly (not a glob - see [tomgrv/scripts](https://github.com/tomgrv/scripts)'s
   own `package.json` for the same convention), so `npm install`/`npm ls`
   understand the whole graph and `zz_use`-resolvable folders that
   reference each other as real `"dependencies"` (`@<org>/<repo>-<name>`
   here) actually work.
5. **Tests**: `sh -n`/`bash -n` every script at minimum; `bats` for
   anything with pure logic worth covering (see `tests/` here). Anything
   that genuinely needs a live target system (this repo's own apt/Helm/k3s
   installs) won't have automated coverage from within the repo alone -
   say so rather than skipping the question.
