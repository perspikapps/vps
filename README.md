# vps

One-line bootstrapper that turns a fresh Ubuntu VPS into a secured
management box running Cockpit and a single-node k3s/Rancher cluster,
with Traefik as a public HTTP/HTTPS ingress. Cockpit, Rancher, ArgoCD,
and the Traefik dashboard are Tailscale-only; the ingress itself (80/443)
is public on purpose - see [Security model](#security-model). ArgoCD and
[Epinio](#epinio-deploy-apps-from-source) are optional, opt-in steps (see
[Running a single step](#running-a-single-step-or-a-subset)) - everything
else runs by default. Every step can also be turned back off later without
reinstalling anything else - see [Removing a feature](#removing-a-feature-updown-per-step).

```bash
curl -fsSL https://raw.githubusercontent.com/perspikapps/vps/main/setup.sh | sudo bash
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
     bash setup.sh
```

## Running a single step (or a subset)

`setup.sh` runs nine numbered steps in order: `system` (01), `security`
(02), `tailscale` (03), `cockpit` (04), `k3s` (05, includes Traefik
configuration), `rancher` (06), `dockermanager` (07), `argocd` (08), and
`epinio` (09). All of them run by default **except `argocd` and `epinio`,
which are opt-in** (both are heavy - see their own sections below - and
Epinio specifically is of little use without a real domain). Three flag
families control which of them run:

- **`--skip-<step>`** - run everything *except* the named step(s).
- **`--with-<step>`** - turn on an opt-in step (currently `argocd` or
  `epinio`) that's off by default; harmless (a no-op) on a step that's
  already on by default.
- **`--only-<step>`** - run *only* the named step(s), regardless of its
  default; pass it more than once to run a few together. Any `--only-*`
  flag overrides every `--skip-*`/`--with-*` flag on the command line.

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

# Full default run, plus the opt-in ArgoCD step:
sudo bash /tmp/setup.sh --with-argocd
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

### Dependencies between steps

`rancher`, `argocd`, and `epinio` all need `k3s` (they deploy onto the
cluster it creates). Enabling any of them auto-enables `k3s` too, even if
you didn't ask for it explicitly:

```bash
# k3s isn't named here, but this still installs it - rancher needs it:
sudo bash setup.sh --only-rancher
# -> [vps-setup] Also enabling 'k3s' (required by 'rancher').
```

The same table is used in reverse for [`--down-<step>`](#removing-a-feature-updown-per-step):
bringing `k3s` down while `rancher`/`argocd`/`epinio` are still enabled is
refused, since it would leave them broken.

## Interactive menu

Run `setup.sh` with **no arguments**, on an actual terminal (an SSH
session, not `curl ... | sudo bash`, which pipes the script itself into
stdin and never triggers this), to get a menu instead of having to
remember flag names:

```bash
sudo bash /tmp/setup.sh
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
sudo bash /tmp/setup.sh --down-argocd

# Remove more than one step in the same run:
sudo bash /tmp/setup.sh --down-argocd --down-epinio

# Add ArgoCD and remove Epinio in the same run:
sudo bash /tmp/setup.sh --with-argocd --down-epinio
```

A step whose dependency is still enabled refuses to come down, so you
don't accidentally break something still running:

```bash
sudo bash /tmp/setup.sh --down-k3s
# [vps-setup] Refusing to bring 'k3s' down: 'rancher' depends on it and is still enabled.
# [vps-setup] Also pass --down-rancher, or --force-down to override (may leave 'rancher' broken).
```

Either bring the dependent step down in the same run (`--down-k3s
--down-rancher --down-argocd --down-epinio`, to remove the whole cluster
cleanly), or pass `--force-down` if you really want to pull `k3s` out from
under something still enabled.

What each step's `down` action actually does - and doesn't - undo:

| Step | `down` removes | Left in place |
|---|---|---|
| `system` | *(no down action - a base package upgrade, nothing to undo)* | everything |
| `security` | ufw rules (disables ufw entirely), sshd hardening, fail2ban jail | the admin user/password `up` created, if any |
| `tailscale` | logs out of the tailnet, disables `tailscaled` | the `tailscale` package itself (`PURGE_TAILSCALE=true` to remove it too) |
| `cockpit` | the Cockpit packages and socket config | nothing else depends on it |
| `k3s` | k3s itself (via its own uninstaller) - **takes Rancher/ArgoCD/Epinio down with it** | - |
| `rancher` | the Helm release and its namespace | cert-manager (shared with Epinio) |
| `dockermanager` | cockpit-dockermanager, cockpit-packagekit, cockpit-files | Docker itself (`REMOVE_DOCKER=true` to also remove it) |
| `argocd` | the Helm release and its namespace | k3s, cert-manager |
| `epinio` | the Helm release, its namespace, and the `epinio` CLI | k3s, cert-manager, Traefik |

Each script also accepts the action directly if you'd rather run it
without going through `setup.sh` (e.g. from an existing `/opt/vps-setup`
checkout):

```bash
sudo bash scripts/08-argocd.sh down
sudo bash scripts/08-argocd.sh up     # same as calling it with no argument
```

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
(`https://rancher.tailnet-name.ts.net:7083`) from a machine on the same
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

- `setup.sh` - leading script: clones/updates this repo, resolves which
  steps run (flags, the [interactive menu](#interactive-menu), and
  step dependencies), and runs `scripts/*` in order, idempotent and
  re-runnable, either `up` or [`down`](#removing-a-feature-updown-per-step).
- `cloud-init/kairos-vps-setup.yaml` - cloud-init/Kairos user-data that
  runs `setup.sh` unattended on first boot.
- `network.yaml` - single source of truth for every port this setup opens
  and whether it's public or Tailscale-only - see
  [Network config](#network-config-networkyaml).
- `lib/common.sh` - shared logging/retry/idempotency helpers sourced by
  every script (style borrowed from `devcontainers/features` common-utils:
  strict bash mode, non-interactive apt, "already done" checks); `net_port`/
  `net_access` for reading `network.yaml`; and `dispatch_action`/
  `helm_teardown`, the shared plumbing behind every script's `up`/`down`
  actions.
- `scripts/01-system-update.sh` - apt update/upgrade, base tooling,
  unattended security upgrades.
- `scripts/02-security-harden.sh` - optional non-root admin user, ufw
  (default-deny inbound, rules generated from `network.yaml`: SSH and
  Traefik's 80/443 public, everything else Tailscale-only), sshd
  hardening, fail2ban, and a Cockpit/console login password.
- `scripts/03-tailscale.sh` - installs Tailscale, enables `tailscaled` as a
  systemd service, and joins the tailnet.
- `scripts/04-cockpit.sh` - installs Cockpit, served on ports 9080/9083.
- `scripts/05-k3s.sh` - installs k3s (Traefik enabled), kubectl, Helm, and
  configures Traefik as a public HTTP/HTTPS ingress with a Let's Encrypt
  certResolver and a Tailscale-only dashboard - see
  [Traefik ingress](#traefik-ingress-lets-encrypt-and-the-dashboard).
- `scripts/06-rancher.sh` - installs cert-manager (required by Rancher's
  self-signed TLS even with ingress disabled) and the latest Rancher via
  Helm, exposed on ports 7080/7083 through k3s's built-in ServiceLB.
- `scripts/07-cockpit-dockermanager.sh` - installs `cockpit-packagekit`,
  `cockpit-files`, Docker (`docker.io`, as a dependency), and the
  third-party [cockpit-dockermanager](https://github.com/chrisjbawden/cockpit-dockermanager)
  plugin for managing Docker containers/images from Cockpit.
- `scripts/08-argocd.sh` - installs ArgoCD via Helm for GitOps-managed
  deployments onto the k3s cluster, exposed on ports 7090/7093 through
  k3s's built-in ServiceLB.
- `scripts/09-epinio.sh` - installs [Epinio](https://epinio.io) via Helm
  for deploying apps straight from source, routed through Traefik's
  existing ingress rather than a dedicated port - see
  [Epinio (deploy apps from source)](#epinio-deploy-apps-from-source).
- `scripts/99-summary.sh` - prints connection info, the Tailscale URL, and
  the Cockpit/Rancher/ArgoCD/Epinio credentials at the end.

## Network config (`network.yaml`)

Every port this repo opens, and whether it's public or Tailscale-only,
lives in one file: `network.yaml`. Each entry looks like:

```yaml
- name: rancher_http
  port: 7080
  access: tailscale   # or: public
  app: rancher        # optional, informational
  note: "..."         # optional, becomes the ufw rule's comment
```

`scripts/02-security-harden.sh` reads the whole file and builds ufw's
rules from it generically - there's no per-service ufw logic left in that
script, just a loop over `network.yaml`'s entries. Every other script
that binds a port (Cockpit, Rancher, Traefik's dashboard, ArgoCD) reads
its own default from the same file via `lib/common.sh`'s `net_port()`
helper, so the port ufw opens and the port the app actually listens on
can't drift apart.

To change a default port for good, edit `network.yaml` and re-run the
affected step(s) (e.g. `--only-security --only-rancher` after changing
`rancher_http`). To override a port for a single run without editing the
file, use its env var - the name is always the entry's `name`, upper-cased,
with `_PORT` appended: `rancher_http` -> `RANCHER_HTTP_PORT`, `ssh` ->
`SSH_PORT`, and so on.

Lookups are done with [mikefarah/yq](https://github.com/mikefarah/yq) (a
standalone Go binary, auto-installed to `/usr/local/bin/yq` the first
time any script needs it) - deliberately not Ubuntu's `yq` apt package,
which is a different, jq-based tool with incompatible filter syntax.

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

Because of this, **`setup.sh` refuses to run at all if the Tailscale step
is enabled but `TAILSCALE_AUTHKEY` is unset** - proceeding anyway would
lock down ufw and leave every Tailscale-only service unreachable by
anything. Pass `--skip-tailscale` if you genuinely want to run without
Tailscale (you can join manually later with `tailscale up`, then `sudo
bash setup.sh --only-tailscale`).

## Traefik ingress: Let's Encrypt and the dashboard

`scripts/05-k3s.sh` leaves k3s's bundled Traefik enabled (rather than
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
  This makes the resolver *available* - it doesn't issue anything by
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
  points the resolver at Let's Encrypt's *staging* environment - browsers
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
  password - separate from SSH, which stays key-only. `scripts/02-security-harden.sh`
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
doesn't run on a plain `setup.sh` with no flags.

`scripts/08-argocd.sh` installs [ArgoCD](https://argo-cd.readthedocs.io/)
via the `argo/argo-cd` Helm chart onto the k3s cluster from `scripts/05`,
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
`Pending`/`ImagePullBackOff`), either just re-run `sudo bash setup.sh
--only-argocd` (helm resumes the same release without re-pulling cached
images), or set `ARGOCD_INSTALL_TIMEOUT` to a larger value first.

Point ArgoCD at your Git repos and `Application` manifests the usual way
(`argocd repo add`, `argocd app create`, or the UI) once you've logged in
- see the [ArgoCD docs](https://argo-cd.readthedocs.io/en/stable/getting_started/)
for that workflow; this repo only handles getting ArgoCD itself installed
and reachable.

Both credentials, along with the Tailscale IP/URL to reach them on, are
printed by `scripts/99-summary.sh` at the end of the install (and any time
you re-run it: `sudo bash /opt/vps-setup/scripts/99-summary.sh`).

## Epinio (deploy apps from source)

Opt-in - pass `--with-epinio` (or `--only-epinio`) to install it; it
doesn't run on a plain `setup.sh` with no flags.

`scripts/09-epinio.sh` installs [Epinio](https://epinio.io) - "from app to
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
`scripts/06-rancher.sh` uses, so it reuses Rancher's cert-manager if that
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
  `Pending`/`ImagePullBackOff`, then just re-run `sudo bash setup.sh
  --only-epinio` (helm resumes the same release without re-pulling cached
  images), or set `EPINIO_INSTALL_TIMEOUT` higher first.

The login and dashboard URL are printed by `scripts/99-summary.sh` like
every other step's credentials.

## Key environment variables

All `*_PORT` variables below are per-run overrides of a default that
actually lives in [`network.yaml`](#network-config-networkyaml) - edit
that file to change a default for good, or set the env var for one run.

| Variable | Default | Purpose |
|---|---|---|
| `VPS_ADMIN_USER` | unset | Create this sudo user |
| `VPS_ADMIN_SSH_KEY` | unset | Authorized key for the admin user and root |
| `VPS_ADMIN_PASSWORD` | random | Cockpit/console login password (separate from SSH) |
| `SSH_PORT` | `22` | SSH port kept open publicly |
| `TAILSCALE_AUTHKEY` | unset | Auto-join a tailnet (**required** unless `--skip-tailscale`) |
| `TAILSCALE_EXTRA_ARGS` | unset | Extra flags appended to `tailscale up` |
| `COCKPIT_HTTP_PORT` / `COCKPIT_HTTPS_PORT` | `9080` / `9083` | Cockpit ports (`9xxx`) |
| `RANCHER_HTTP_PORT` / `RANCHER_HTTPS_PORT` | `7080` / `7083` | Rancher ports (`7xxx`) |
| `RANCHER_HOSTNAME` | node IP | Hostname used in Rancher's cert |
| `RANCHER_BOOTSTRAP_PASSWORD` | random | Rancher initial admin password |
| `INSTALL_DOCKER` | `true` | Install `docker.io` for cockpit-dockermanager to manage |
| `COCKPIT_DOCKERMANAGER_VERSION` | `latest` | [cockpit-dockermanager](https://github.com/chrisjbawden/cockpit-dockermanager) release tag to install |
| `TRAEFIK_ACME_EMAIL` | placeholder | Let's Encrypt contact email - set this to a real address |
| `TRAEFIK_ACME_STAGING` | `true` | Use Let's Encrypt's staging (untrusted, no rate limit) vs. production certs |
| `TRAEFIK_DASHBOARD_PORT` | `8088` | Traefik dashboard port (Tailscale-only) |
| `ARGOCD_HTTP_PORT` / `ARGOCD_HTTPS_PORT` | `7090` / `7093` | ArgoCD ports (`7xxx`, alongside Rancher) |
| `ARGOCD_CHART_VERSION` | latest | Pin the `argo/argo-cd` Helm chart version |
| `ARGOCD_INSTALL_TIMEOUT` | `15m` | How long to wait for ArgoCD's pods to come up |
| `EPINIO_DOMAIN` | `<node-ip>.sslip.io` | Wildcard domain Epinio's Ingresses use - set to a real domain |
| `EPINIO_INGRESS_CLASS` | `traefik` | IngressClass Epinio's Ingresses are pinned to (reuses k3s's bundled Traefik) |
| `EPINIO_TLS_ISSUER` | `epinio-ca` | cert-manager ClusterIssuer: `epinio-ca`, `selfsigned-issuer`, `letsencrypt-staging`, or `letsencrypt-production` |
| `EPINIO_ADMIN_PASSWORD` | random | Epinio admin login password |
| `EPINIO_CHART_VERSION` | latest | Pin the `epinio/epinio` Helm chart version |
| `EPINIO_INSTALL_TIMEOUT` | `15m` | How long to wait for Epinio's pods to come up |
| `CERT_MANAGER_VERSION` | latest | Pin cert-manager's chart version (shared by Rancher and Epinio) |

Ports follow a per-app range so they're easy to tell apart at a glance:
Cockpit `9xxx`, Rancher and ArgoCD `7xxx`, Traefik dashboard `8xxx` - the
ingress itself is always 80/443, per HTTP/HTTPS convention, not part of
this scheme.

Each script can also be run standalone from the `scripts/` directory
after `lib/common.sh` is present alongside it (this is what `setup.sh
--only-<step>`, described in
[Running a single step (or a subset)](#running-a-single-step-or-a-subset)
above, does for you), for example to re-run just the Rancher install
with a new hostname:

```bash
sudo RANCHER_HOSTNAME=new.example.com bash scripts/06-rancher.sh
```

Every script also takes an explicit `up` or `down` action as its first
argument (`up` is the default, so the invocation above is really `...
bash scripts/06-rancher.sh up`) - see
[Removing a feature](#removing-a-feature-updown-per-step) for what each
step's `down` does.

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
`scripts/06-rancher.sh`, `scripts/08-argocd.sh`, and `scripts/09-epinio.sh`
all check for `kubectl`/`helm` explicitly and `die` with a clear message
in that case; if you hit a silent stop anywhere else, please open an
issue with the exact command you ran and the last few lines of output.
