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

## Layout

- `setup.sh` - leading script: clones/updates this repo, runs `scripts/*`
  in order, idempotent and re-runnable.
- `lib/common.sh` - shared logging/retry/idempotency helpers sourced by
  every script (style borrowed from `devcontainers/features` common-utils:
  strict bash mode, non-interactive apt, "already done" checks).
- `scripts/01-system-update.sh` - apt update/upgrade, base tooling,
  unattended security upgrades.
- `scripts/02-security-harden.sh` - optional non-root admin user, ufw
  (default-deny inbound; SSH public, everything else Tailscale-only),
  sshd hardening, fail2ban.
- `scripts/03-tailscale.sh` - installs Tailscale and joins the tailnet.
- `scripts/04-cockpit.sh` - installs Cockpit, served on ports 9080/9083.
- `scripts/05-k3s.sh` - installs k3s (Traefik disabled), kubectl, Helm.
- `scripts/06-rancher.sh` - installs the latest Rancher via Helm, exposed
  on ports 8080/8083 through k3s's built-in ServiceLB.
- `scripts/99-summary.sh` - prints connection info at the end.

## Security model

The server is only supposed to be reachable from the public internet on
the SSH port. Everything else - Cockpit, Rancher, the k3s API - is bound
by `ufw` to the `tailscale0` interface only, so you must join the same
tailnet to reach them. Set `ALLOW_PUBLIC_WEB=true` if you want ports 80/443
open publicly (e.g. to front Rancher with your own ingress/TLS setup).

## Key environment variables

| Variable | Default | Purpose |
|---|---|---|
| `VPS_ADMIN_USER` | unset | Create this sudo user |
| `VPS_ADMIN_SSH_KEY` | unset | Authorized key for the admin user and root |
| `SSH_PORT` | `22` | SSH port kept open publicly |
| `ALLOW_PUBLIC_WEB` | `false` | Also open 80/443 publicly |
| `TAILSCALE_AUTHKEY` | unset | Auto-join a tailnet |
| `COCKPIT_HTTP_PORT` / `COCKPIT_HTTPS_PORT` | `9080` / `9083` | Cockpit ports |
| `RANCHER_HTTP_PORT` / `RANCHER_HTTPS_PORT` | `8080` / `8083` | Rancher ports |
| `RANCHER_HOSTNAME` | node IP | Hostname used in Rancher's cert |
| `RANCHER_BOOTSTRAP_PASSWORD` | random | Rancher initial admin password |

Each script can also be run standalone from the `scripts/` directory
after `lib/common.sh` is present alongside it, for example to re-run just
the Rancher install with a new hostname:

```bash
sudo RANCHER_HOSTNAME=new.example.com bash scripts/06-rancher.sh
```
