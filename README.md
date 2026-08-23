# vps

One-line bootstrapper that turns a fresh Ubuntu VPS into a secured,
Tailscale-only management box running Cockpit and a single-node
k3s/Rancher cluster.

```bash
curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/setup.sh | sudo bash
```

Run with `-h` for flags (`--skip-tailscale`, `--skip-rancher`, etc.), or set
env vars beforehand, e.g.:

```bash
sudo TAILSCALE_AUTHKEY=tskey-... \
     VPS_ADMIN_USER=ops VPS_ADMIN_SSH_KEY="ssh-ed25519 AAAA..." \
     RANCHER_HOSTNAME=rancher.example.internal \
     bash setup.sh
```

## Running a single step (or a subset)

`setup.sh` runs nine numbered steps in order: `system` (01), `security`
(02), `tailscale` (03), `cockpit` (04), `k3s` (05), `rancher` (06),
`dockermanager` (07), `laranode` (08), and `coder` (09). Three flag
families control which of them run:

- **`--skip-<step>`** - run everything *except* the named step(s).
- **`--only-<step>`** - run *only* the named step(s); pass it more than
  once to run a few together. Any `--only-*` flag overrides every
  `--skip-*`/`--with-*` flag on the command line.
- **`--with-<step>`** - `laranode` and `coder` are opt-in (see
  [Laranode](#laranode-optional-lamp-hosting-panel) and
  [Coder](#coder-optional-dev-environment-platform) below) and skipped by
  default even on a full run; `--with-laranode`/`--with-coder` turns one
  on for that run.

When you already have `setup.sh` on disk (e.g. after the
[full copy-paste example](#full-copy-paste-example)'s `-o /tmp/setup.sh`
download), pass flags after the filename like any script:

```bash
# Re-run just Rancher, e.g. after changing RANCHER_HOSTNAME:
sudo RANCHER_HOSTNAME=new.example.com bash /tmp/setup.sh --only-rancher

# Re-run Cockpit and the dockermanager plugin together, skipping everything else:
sudo bash /tmp/setup.sh --only-cockpit --only-dockermanager

# Full run except Rancher (e.g. you're not using Kubernetes on this box):
sudo bash /tmp/setup.sh --skip-rancher --skip-k3s
```

> [!WARNING]
> **With the piped one-liner (`curl ... | sudo bash`), you cannot just
> append flags after `bash`** - `sudo bash --only-rancher` fails with
> `bash: --only-rancher: invalid option`, because bash parses
> `--only-rancher` as an option *to bash itself* (it looks like one:
> `--only-rancher` starts with `--`, same shape as bash's own
> `--norc`/`--posix`/etc.), not as an argument to hand the script being
> read from stdin. You must add `-s --` first: `-s` tells bash to read
> the script from stdin, and `--` marks the end of bash's own options so
> everything after it is passed through as `$1`, `$2`, ... to `setup.sh`:
>
> ```bash
> curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/setup.sh \
>   | sudo bash -s -- --only-rancher
> ```
>
> This composes with env vars the usual way (see the
> [sudo env-var gotcha](#running-from-a-non-standard-branch-or-fork)
> above - put them on the `sudo` line, not in a plain `export`):
>
> ```bash
> curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/setup.sh \
>   | sudo RANCHER_HOSTNAME=new.example.com bash -s -- --only-rancher
> ```

This is equivalent to (and a convenience wrapper around) invoking a
script directly, as shown in [Layout](#layout) below - `--only-rancher`
just means "run `scripts/06-rancher.sh` through `setup.sh`'s usual repo
clone/update and final summary, instead of calling it by hand." Because
every script is idempotent, re-running a single step to pick up a
changed env var (like `RANCHER_HOSTNAME` above) is safe and won't disturb
the others. See `-h`/`--help` for the full flag list.

## Full copy-paste example

A realistic one-shot install on a fresh Ubuntu VPS, run as root right after
first boot. Replace the SSH key and auth key with your own (see
[Getting the keys you'll need](#getting-the-keys-youll-need) below):

```bash
curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/setup.sh -o /tmp/setup.sh

VPS_ADMIN_USER=ops \
VPS_ADMIN_SSH_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... you@laptop" \
TAILSCALE_AUTHKEY="tskey-auth-xxxxxxxxxxxx-xxxxxxxxxxxxxxxxxxxxxxxxxxxx" \
RANCHER_HOSTNAME="rancher.tailnet-name.ts.net" \
RANCHER_BOOTSTRAP_PASSWORD="$(openssl rand -base64 24)" \
bash /tmp/setup.sh
```

This creates the `ops` sudo user with your key, disables SSH password
login, joins your tailnet immediately, and installs Cockpit + k3s +
Rancher. When it finishes, connect over Tailscale and open Cockpit
(`https://<tailscale-ip>:9080`) and Rancher
(`https://rancher.tailnet-name.ts.net:8083`) from a machine on the same
tailnet. Save the printed Rancher bootstrap password (also written to
`/root/.rancher-bootstrap-password`) to log in.

## Running from a non-standard branch or fork

The one-liner above always fetches `setup.sh` from `main`, but `setup.sh`
itself clones the repo again to install `scripts/*` - so to test a branch
end-to-end you need to point *both* fetches at it with `VPS_SETUP_REPO_REF`.

> [!WARNING]
> **`export FOO=bar` then `... | sudo bash` will NOT work.** `sudo` resets
> the environment by default, so a plain shell `export` is invisible to the
> command it runs - `setup.sh` will silently fall back to `main` even
> though `echo $VPS_SETUP_REPO_REF` shows the right value in your shell.
> Either put the assignment directly on the `sudo` line (it is passed
> through even with env reset on), or use `sudo -E`. Don't do this:
>
> ```bash
> export VPS_SETUP_REPO_REF=my-branch          # WRONG: lost by sudo
> curl -fsSL ".../my-branch/setup.sh" | sudo bash
> ```

Piped directly (no intermediate file), with the var set on the `sudo` line
so it survives:

```bash
BRANCH=claude/vps-setup-ubuntu-scripts-br4ddo

curl -fsSL "https://raw.githubusercontent.com/perspikapps/vps/${BRANCH}/setup.sh" \
  | sudo VPS_SETUP_REPO_REF="$BRANCH" bash
```

Or equivalently, keep your `export` but tell `sudo` to preserve it with `-E`
(only works if your sudoers config allows it - the explicit form above
always works and needs no special sudoers setup):

```bash
export VPS_SETUP_REPO_REF=claude/vps-setup-ubuntu-scripts-br4ddo
curl -fsSL "https://raw.githubusercontent.com/perspikapps/vps/${VPS_SETUP_REPO_REF}/setup.sh" \
  | sudo -E bash
```

Downloading to a file first (useful when passing several variables, as in
the [full example](#full-copy-paste-example) above) works the same way -
put every variable on the same line as `sudo`, before `bash`:

```bash
BRANCH=claude/vps-setup-ubuntu-scripts-br4ddo

curl -fsSL "https://raw.githubusercontent.com/perspikapps/vps/${BRANCH}/setup.sh" -o /tmp/setup.sh

sudo VPS_SETUP_REPO_REF="$BRANCH" \
     VPS_ADMIN_USER=ops VPS_ADMIN_SSH_KEY="ssh-ed25519 AAAA..." \
     bash /tmp/setup.sh
```

Env vars for this:

| Variable | Default | Purpose |
|---|---|---|
| `VPS_SETUP_REPO_URL` | `https://github.com/perspikapps/vps.git` | Clone a fork instead |
| `VPS_SETUP_REPO_REF` | `main` | Branch, tag, or commit to check out |
| `VPS_SETUP_DIR` | `/opt/vps-setup` | Where the repo is cloned/updated |

To point at a fork as well as a branch, set both:

```bash
sudo VPS_SETUP_REPO_URL=https://github.com/<you>/vps.git \
     VPS_SETUP_REPO_REF=my-feature \
     bash /tmp/setup.sh
```

`setup.sh` re-clones into `VPS_SETUP_DIR` on every run (`git fetch` +
`reset --hard` if it's already a checkout), so re-running it after pushing
new commits to the same branch picks them up automatically - no need to
re-download `setup.sh` itself unless you're switching branches/forks.

## Getting the keys you'll need

**SSH key pair** (for `VPS_ADMIN_SSH_KEY`) - generate one on your own
machine, never on the VPS:

```bash
ssh-keygen -t ed25519 -C "you@laptop" -f ~/.ssh/vps_ed25519
cat ~/.ssh/vps_ed25519.pub   # paste this whole line as VPS_ADMIN_SSH_KEY
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
Without this variable, `scripts/03-tailscale.sh` still installs Tailscale;
just run `tailscale up` manually afterwards and follow the login link.

**Rancher bootstrap password** (for `RANCHER_BOOTSTRAP_PASSWORD`) - any
string works; generate a random one with:

```bash
openssl rand -base64 24
```

If you don't set it, `scripts/06-rancher.sh` generates and saves one for
you automatically.

## Provisioning via cloud-init / Kairos

[`cloud-init/kairos-vps-setup.yaml`](cloud-init/kairos-vps-setup.yaml) is a
`#cloud-config` user-data file that runs `setup.sh` unattended on first
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
[`export ... | sudo bash` env-var gotcha](#running-from-a-non-standard-branch-or-fork)
entirely - there's no `sudo` involved.

## Layout

- `setup.sh` - leading script: clones/updates this repo, runs `scripts/*`
  in order, idempotent and re-runnable.
- `cloud-init/kairos-vps-setup.yaml` - cloud-init/Kairos user-data that
  runs `setup.sh` unattended on first boot.
- `lib/common.sh` - shared logging/retry/idempotency helpers sourced by
  every script (style borrowed from `devcontainers/features` common-utils:
  strict bash mode, non-interactive apt, "already done" checks).
- `scripts/01-system-update.sh` - apt update/upgrade, base tooling,
  unattended security upgrades.
- `scripts/02-security-harden.sh` - optional non-root admin user, ufw
  (default-deny inbound; SSH public, everything else Tailscale-only),
  sshd hardening, fail2ban, and a Cockpit/console login password.
- `scripts/03-tailscale.sh` - installs Tailscale, enables `tailscaled` as a
  systemd service, and joins the tailnet.
- `scripts/04-cockpit.sh` - installs Cockpit, served on ports 9080/9083.
- `scripts/05-k3s.sh` - installs k3s (Traefik disabled), kubectl, Helm.
- `scripts/06-rancher.sh` - installs cert-manager (required by Rancher's
  self-signed TLS even with ingress disabled) and the latest Rancher via
  Helm, exposed on ports 8080/8083 through k3s's built-in ServiceLB.
- `scripts/07-cockpit-dockermanager.sh` - installs `cockpit-packagekit`,
  `cockpit-files`, Docker (`docker.io`, as a dependency), and the
  third-party [cockpit-dockermanager](https://github.com/chrisjbawden/cockpit-dockermanager)
  plugin for managing Docker containers/images from Cockpit.
- `scripts/08-laranode.sh` - **opt-in** (`--with-laranode`/`--only-laranode`):
  installs [Laranode](https://laranode.com), a LAMP hosting panel, natively
  on the host via its official installer.
- `scripts/09-coder.sh` - **opt-in** (`--with-coder`/`--only-coder`):
  deploys [Coder](https://coder.com) plus a minimal Postgres as Helm
  releases into k3s, exposed on port 8090.
- `scripts/99-summary.sh` - prints connection info, the Tailscale URL, and
  the Cockpit/Rancher/Coder credentials at the end.

## Security model

The server is only supposed to be reachable from the public internet on
the SSH port. Everything else - Cockpit, Rancher, the k3s API - is bound
by `ufw` to the `tailscale0` interface only, so you must join the same
tailnet to reach them. Set `ALLOW_PUBLIC_WEB=true` if you want ports 80/443
open publicly (e.g. to front Rancher with your own ingress/TLS setup).

Because of this, **`setup.sh` refuses to run at all if the Tailscale step
is enabled but `TAILSCALE_AUTHKEY` is unset** - proceeding anyway would
lock down ufw and leave Cockpit/Rancher/k3s unreachable by anything. Pass
`--skip-tailscale` if you genuinely want to run without Tailscale (you can
join manually later with `tailscale up`, then `sudo bash setup.sh
--only-tailscale`).

## Laranode (optional LAMP hosting panel)

`scripts/08-laranode.sh` is **opt-in** (`--with-laranode` on a full run, or
standalone with `--only-laranode`) and installs
[Laranode](https://laranode.com), an open-source Laravel/LAMP hosting
control panel, via its official installer. Unlike everything else in this
repo, Laranode has no container image or Helm chart upstream - it's a
traditional VPS panel that installs its own Apache/MySQL/PHP-FPM stack
directly on the host, so it runs natively rather than in k3s.

- **Public by default, on purpose**: the installer opens ufw for 80, 443,
  and 8080 (its Reverb websocket service) to the whole internet, and this
  repo leaves that in place - unlike Cockpit/Rancher, Laranode's entire
  purpose is hosting public-facing websites, and its one-click Let's
  Encrypt feature needs port 80 reachable for ACME HTTP-01 validation.
  Set `LARANODE_TAILSCALE_ONLY=true` if you want it private instead (this
  also disables its Let's Encrypt issuance).
- **Port collision**: Laranode hardcodes port 8080 for Reverb, the same as
  this repo's default `RANCHER_HTTP_PORT`. If you're installing both, set
  `RANCHER_HTTP_PORT` to something else first.
- Credentials (MySQL root password, Laranode's own DB user password) are
  generated and printed once by the installer itself - not saved to a
  file by Laranode, and not re-shown by `scripts/99-summary.sh`, so copy
  them down when you see them.
- **PHP/Composer workaround**: Laranode's installer adds `ppa:ondrej/php`
  and installs PHP from it, but that PPA lags brand-new Ubuntu releases by
  months (it 404s outright on 26.04/"resolute" as of this writing) - and
  since the installer runs with `set -e` disabled, a failure there doesn't
  stop it; it carries on into `composer install`/`php artisan ...` with no
  PHP at all, failing loudly on each one and leaving a half-built install
  (repo cloned, assets built, ufw rules added, but no `vendor/`, `.env`,
  or migrations). `scripts/08-laranode.sh` works around this by
  pre-installing PHP 8.4 + Composer from
  [Sury's repo](https://packages.sury.org/php/) (the PPA's own
  replacement recommendation for unsupported releases) before handing off
  to the installer, so its own broken PPA step becomes a harmless no-op.
  Sury can lag too, though - if the running release isn't supported there
  either, it falls back to Sury's Ubuntu 24.04 ("noble") packages (PHP
  userspace packages are ABI-compatible across adjacent Ubuntu releases,
  a common, safe workaround), and only fails fast with a clear message if
  neither works. It also detects and removes a partial install from a
  previous failed run (its `git clone` isn't idempotent) before retrying.
- **Sudoers workaround**: the installer also writes a sudoers rule with a
  wildcard inside a command *argument* (`/bin/rm
  .../sites-available/*.conf`) - sudo only ever permits wildcards in the
  command path, never in arguments, so this specific clause is invalid on
  any system and sudo silently skips it (with a recurring "wildcards are
  not allowed in command arguments" warning every time the file is
  parsed). That permission was never actually granted, so
  `scripts/08-laranode.sh` removes just that clause - verified safe with
  `visudo -c` before touching `/etc/sudoers`, and left untouched if that
  check fails.

## Coder (optional dev-environment platform)

`scripts/09-coder.sh` is **opt-in** (`--with-coder` on a full run, or
standalone with `--only-coder`) and deploys
[Coder](https://coder.com), a self-hosted remote development platform, as
a Helm release into the k3s cluster from `scripts/05` - it then shows up
in Rancher's own Apps view like any other in-cluster Helm release, since
Rancher lists Helm releases already present in the cluster regardless of
how they were installed.

- Coder's chart ships no bundled database, so this also deploys a minimal
  single-replica Postgres (official `postgres` image + a PVC on k3s's
  default `local-path` StorageClass) - fine for this repo's single-node
  scope, not meant to be HA.
- Exposed on `CODER_HTTP_PORT` (default `8090`) via k3s's built-in
  ServiceLB, the same pattern as Rancher - Tailscale-only by default,
  same as everything else (see [Security model](#security-model)).
- Runs over plain HTTP inside the cluster: the transport is already
  encrypted by Tailscale itself. Set `coder.tls.secretNames` yourself via
  `CODER_EXTRA_HELM_ARGS` if you want the chart to terminate TLS instead.
- The initial admin user is created non-interactively (`coder server
  create-admin-user`, run as a one-off Kubernetes Job), since Coder has no
  bootstrap-password chart value the way Rancher does. Username
  (`CODER_ADMIN_USERNAME`, default `admin`), email (`CODER_ADMIN_EMAIL`),
  and password (`CODER_ADMIN_PASSWORD`, default random, saved to
  `/root/.coder-admin-password`) are all overridable.

## Cockpit and Rancher logins

- **Cockpit** authenticates via PAM against a real Linux account and
  password - separate from SSH, which stays key-only. `scripts/02-security-harden.sh`
  sets a password for `VPS_ADMIN_USER` (or `root` if that's unset): either
  `VPS_ADMIN_PASSWORD` if you set it, or a random one saved to
  `/root/.cockpit-admin-password` (username in `/root/.cockpit-admin-user`).
- **Rancher** username is always `admin`; the initial password is
  `RANCHER_BOOTSTRAP_PASSWORD` if set, otherwise a random one saved to
  `/root/.rancher-bootstrap-password`. Rancher prompts you to change it on
  first login.

Both credentials, along with the Tailscale IP/URL to reach them on, are
printed by `scripts/99-summary.sh` at the end of the install (and any time
you re-run it: `sudo bash /opt/vps-setup/scripts/99-summary.sh`).

## Key environment variables

| Variable | Default | Purpose |
|---|---|---|
| `VPS_ADMIN_USER` | unset | Create this sudo user |
| `VPS_ADMIN_SSH_KEY` | unset | Authorized key for the admin user and root |
| `VPS_ADMIN_PASSWORD` | random | Cockpit/console login password (separate from SSH) |
| `SSH_PORT` | `22` | SSH port kept open publicly |
| `ALLOW_PUBLIC_WEB` | `false` | Also open 80/443 publicly |
| `TAILSCALE_AUTHKEY` | unset | Auto-join a tailnet (**required** unless `--skip-tailscale`) |
| `TAILSCALE_EXTRA_ARGS` | unset | Extra flags appended to `tailscale up` |
| `COCKPIT_HTTP_PORT` / `COCKPIT_HTTPS_PORT` | `9080` / `9083` | Cockpit ports |
| `RANCHER_HTTP_PORT` / `RANCHER_HTTPS_PORT` | `8080` / `8083` | Rancher ports |
| `RANCHER_HOSTNAME` | node IP | Hostname used in Rancher's cert |
| `RANCHER_BOOTSTRAP_PASSWORD` | random | Rancher initial admin password |
| `INSTALL_DOCKER` | `true` | Install `docker.io` for cockpit-dockermanager to manage |
| `COCKPIT_DOCKERMANAGER_VERSION` | `latest` | [cockpit-dockermanager](https://github.com/chrisjbawden/cockpit-dockermanager) release tag to install |
| `LARANODE_TAILSCALE_ONLY` | `false` | Restrict Laranode's ports to Tailscale instead of leaving them public |
| `CODER_HOSTNAME` | node IP | Hostname used in `CODER_ACCESS_URL` |
| `CODER_HTTP_PORT` | `8090` | Coder's exposed port |
| `CODER_ADMIN_USERNAME` / `CODER_ADMIN_EMAIL` | `admin` / `admin@<hostname>` | Initial Coder admin account |
| `CODER_ADMIN_PASSWORD` | random | Initial Coder admin password |
| `CODER_POSTGRES_PASSWORD` | random | Password for Coder's bundled Postgres |
| `CODER_CHART_VERSION` | latest | Pin the Coder Helm chart version |
| `CODER_EXTRA_HELM_ARGS` | unset | Extra args appended to Coder's `helm upgrade --install` |

Each script can also be run standalone from the `scripts/` directory
after `lib/common.sh` is present alongside it (this is what `setup.sh
--only-<step>`, described in
[Running a single step (or a subset)](#running-a-single-step-or-a-subset)
above, does for you), for example to re-run just the Rancher install
with a new hostname:

```bash
sudo RANCHER_HOSTNAME=new.example.com bash scripts/06-rancher.sh
```

## Troubleshooting: a step fails or "just stops"

Every script runs under `set -euo pipefail` and sources `lib/common.sh`,
which installs an error trap: the first command that fails without being
explicitly handled (i.e. not part of an `if`/`&&`/`||`) prints its exact
file, line number, and the failing command, then the script exits. For
example:

```
[vps-setup] ERROR: command failed (exit 1) at /opt/vps-setup/scripts/06-rancher.sh line 52: helm upgrade --install rancher ...
```

When a step fails during a full `setup.sh` run, it also prints which
numbered step failed and how to re-run just that one after fixing the
issue:

```
[vps-setup] Step 'Rancher install' (06-rancher.sh) failed (exit 1) - see the error above. Fix it and re-run just this step with: sudo bash setup.sh --only-rancher
```

If you ever see a step stop with truly no output at all (not even its own
first `log` line), that most often means a *prerequisite* step was
skipped - e.g. running `--only-rancher` on a box where `--only-k3s` (or a
full run) was never done first, so `kubectl`/`helm` don't exist yet.
`scripts/06-rancher.sh` and `scripts/05-k3s.sh` check for their
prerequisites explicitly and `die` with a clear message in that case; if
you hit a silent stop anywhere else, please open an issue with the exact
command you ran and the last few lines of output.
