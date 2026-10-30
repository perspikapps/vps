<!-- @format -->

# Ansible

Run `vps-setup` from Ansible. The role `vps` installs `vps-setup` on the host
if missing, writes your inputs to `/etc/vps-setup.env`, then runs it unattended
(`ZZ_INTERACTIVE=0`). Steps are idempotent, so the play can be re-run at any time.

```bash
cp ansible/inventory.example.yml inventory.yml   # edit hosts and vps_env
ansible-playbook -i inventory.yml ansible/playbook.yml
```

| Variable                                           | Purpose                                                      |
| -------------------------------------------------- | ------------------------------------------------------------ |
| `vps_env`                                          | Inputs (see the root README "Inputs"), e.g. `TAILSCALE_AUTHKEY` |
| `vps_skip`, `vps_with`, `vps_only`, `vps_down`     | Step lists, same as `--skip-<step>`, `--with-<step>`, ...    |
| `vps_ref`                                          | Branch, tag or commit of this repo to install (default `main`) |

Keep secrets in Ansible Vault. The play reports "changed" on every run because
the steps do not report whether they modified anything.

## Native roles (migration in progress)

`site.yml` runs steps ported to native Ansible (idempotent, real `changed` reporting, no `zz-*` toolchain on the host). Steps not yet ported still run through the legacy `vps` role in `playbook.yml`.

| Step | Native role |
|---|---|
| `vps-system` | `vps_system` (apt, dnf, zypper) |
| `svc-tailscale` | `svc_tailscale` (apt repo on Debian family, official installer elsewhere) |
| `svc-cloudflare` | `svc_cloudflare` (opt-in: `vps_with: [svc-cloudflare]` and `vps_skip: [svc-tailscale]`) |
| `svc-cockpit` | `svc_cockpit` |
| `vps-security` | `vps_security` (ufw or firewalld, sshd, fail2ban, private-ports guard) |

```bash
ansible-playbook -i inventory.yml site.yml --check --diff   # preview
ansible-playbook -i inventory.yml site.yml
```

Role inputs are plain variables with env-lookup defaults (e.g. `vps_system_tz` reads `SYSTEM_TZ`).

Install the collections first: `ansible-galaxy collection install -r requirements.yml`.

### `vps_security` safety net
SSH and firewall changes are made under a rollback timer: if Ansible cannot open a fresh SSH connection afterwards, the host undoes them itself after `vps_security_rollback_seconds` (sshd drop-in removed, firewall disabled), so a bad change never locks you out. The timer is disarmed as soon as the new connection works.

Differences from the shell step:
- root login is closed (`PermitRootLogin no`) only when `vps_admin_user` and `vps_admin_ssh_key` are both set; otherwise it stays `prohibit-password`.
- the sshd drop-in is `00-vps-hardening.conf` (sshd keeps the first value it reads, so the old `99-` file lost to cloud-init's `50-cloud-init.conf`); the old file is removed.
- `MaxAuthTries 3`, `KbdInteractiveAuthentication no`, `ClientAliveInterval` added.
- the firewall is never reset; rules from the old `/var/lib/vps-security-ufw.rules` are left as they are, new rules are tracked in `/var/lib/vps-security-ports.json`.
- extend `vps_security_ports` for steps you enable (Dokploy: 80/443 public, 3000 private; app-coder: 5000 private).

## Adopting a host set up by `vps-setup`

1. Install the collections and fill in `inventory.yml` (copy `inventory.example.yml`); export the secrets you used before (`TAILSCALE_AUTHKEY`, `SYSTEM_ADMIN_USER`, `SYSTEM_ADMIN_SSH_KEY`...).
2. Preview. Nothing is applied; `command`/`shell` tasks are skipped in check mode, so the diff shows files, packages, users and firewall rules only:

   ```bash
   ansible-playbook -i inventory.yml site.yml --check --diff
   ```

3. What the diff should show on an adopted host, and what is expected:
   - `00-vps-hardening.conf` created and `99-vps-setup.conf` removed (sshd rename). `PermitRootLogin` flips to `no` only if `vps_admin_user` and `vps_admin_ssh_key` are set.
   - `/var/lib/vps-security-ports.json` created. The firewall rules themselves should report `ok`; the old `/var/lib/vps-security-ufw.rules` is left untouched.
   - `/etc/vps-network.env` may report one change per key if the shell step stored the value quoted (`'tailscale0'`): the value is the same.
   - The guard script/unit may report a change if whitespace differs, which restarts the guard (a few milliseconds without the DROP rule).
   - Nothing should change in `/root/.vps-secrets.env`: the saved Cockpit password is read back and kept.
   - Package upgrades appear as changes on `vps_system` whenever updates are pending.
4. Keep a second SSH session open, then apply with `ansible-playbook -i inventory.yml site.yml`. If the new SSH config or firewall cut you off, the host reverts them after `vps_security_rollback_seconds`.
5. Run it a second time: it should report `changed=0` (apart from pending package upgrades).
