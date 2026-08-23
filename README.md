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

`setup.sh` runs seven numbered steps in order: `system` (01), `security`
(02), `tailscale` (03), `cockpit` (04), `k3s` (05), `rancher` (06), and
`dockermanager` (07). Two flag families control which of them run:

- **`--skip-<step>`** - run everything *except* the named step(s).
- **`--only-<step>`** - run *only* the named step(s); pass it more than
  once to run a few together. Any `--only-*` flag overrides every
  `--skip-*` flag on the command line.

```bash
# Re-run just Rancher, e.g. after changing RANCHER_HOSTNAME:
sudo RANCHER_HOSTNAME=new.example.com bash setup.sh --only-rancher

# Re-run Cockpit and the dockermanager plugin together, skipping everything else:
sudo bash setup.sh --only-cockpit --only-dockermanager

# Full run except Rancher (e.g. you're not using Kubernetes on this box):
sudo bash setup.sh --skip-rancher --skip-k3s
```

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
- `scripts/03-tailscale.sh` - installs Tailscale and joins the tailnet.
- `scripts/04-cockpit.sh` - installs Cockpit, served on ports 9080/9083.
- `scripts/05-k3s.sh` - installs k3s (Traefik disabled), kubectl, Helm.
- `scripts/06-rancher.sh` - installs cert-manager (required by Rancher's
  self-signed TLS even with ingress disabled) and the latest Rancher via
  Helm, exposed on ports 8080/8083 through k3s's built-in ServiceLB.
- `scripts/07-cockpit-dockermanager.sh` - installs `cockpit-packagekit`,
  `cockpit-files`, Docker (`docker.io`, as a dependency), and the
  third-party [cockpit-dockermanager](https://github.com/chrisjbawden/cockpit-dockermanager)
  plugin for managing Docker containers/images from Cockpit.
- `scripts/99-summary.sh` - prints connection info, the Tailscale URL, and
  the Cockpit/Rancher credentials at the end.

## Security model

The server is only supposed to be reachable from the public internet on
the SSH port. Everything else - Cockpit, Rancher, the k3s API - is bound
by `ufw` to the `tailscale0` interface only, so you must join the same
tailnet to reach them. Set `ALLOW_PUBLIC_WEB=true` if you want ports 80/443
open publicly (e.g. to front Rancher with your own ingress/TLS setup).

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
| `TAILSCALE_AUTHKEY` | unset | Auto-join a tailnet |
| `COCKPIT_HTTP_PORT` / `COCKPIT_HTTPS_PORT` | `9080` / `9083` | Cockpit ports |
| `RANCHER_HTTP_PORT` / `RANCHER_HTTPS_PORT` | `8080` / `8083` | Rancher ports |
| `RANCHER_HOSTNAME` | node IP | Hostname used in Rancher's cert |
| `RANCHER_BOOTSTRAP_PASSWORD` | random | Rancher initial admin password |
| `INSTALL_DOCKER` | `true` | Install `docker.io` for cockpit-dockermanager to manage |
| `COCKPIT_DOCKERMANAGER_VERSION` | `latest` | [cockpit-dockermanager](https://github.com/chrisjbawden/cockpit-dockermanager) release tag to install |

Each script can also be run standalone from the `scripts/` directory
after `lib/common.sh` is present alongside it (this is what `setup.sh
--only-<step>`, described in
[Running a single step (or a subset)](#running-a-single-step-or-a-subset)
above, does for you), for example to re-run just the Rancher install
with a new hostname:

```bash
sudo RANCHER_HOSTNAME=new.example.com bash scripts/06-rancher.sh
```
