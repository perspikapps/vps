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

```bash
ansible-playbook -i inventory.yml site.yml --check --diff   # preview
ansible-playbook -i inventory.yml site.yml
```

Role inputs are plain variables with env-lookup defaults (e.g. `vps_system_tz` reads `SYSTEM_TZ`).
