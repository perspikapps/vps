<!-- @format -->

# cloud-init

First-boot user-data that installs the VPS stack unattended.

Part of [`perspikapps/vps`](https://github.com/perspikapps/vps) - see the root README's [Provision at first boot](../README.md#provision-at-first-boot).

## Usage

[`kairos-vps-setup.yaml`](kairos-vps-setup.yaml) is a `#cloud-config` file: it bootstraps `zz-use` and runs `vps-setup` on first boot. It works with [Kairos](https://kairos.io) Ubuntu images and any cloud-init provider that accepts "User data".

1. Copy the file and fill in the placeholders: your SSH public key (in `users[].ssh_authorized_keys` and `SYSTEM_ADMIN_SSH_KEY`), the Tailscale auth key and `RANCHER_HOSTNAME`.
2. Paste it into the provider's "User data" field (or pass it to Kairos).
3. Follow progress in `/var/log/vps-setup.log`.

`runcmd` already runs as root, so no `sudo` is needed there.
