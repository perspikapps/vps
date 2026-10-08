# Changelog

## 2.0.0 (2026-10-08)

*Commits from: v1.1.0..HEAD*

### 💥 BREAKING CHANGES

- install-feature, configure-feature and resolve-context are replaced by feature-install, feature-configure and feature-context; requires tomgrv/scripts v2, tomgrv/actions v4 and devcontainer-features v10.
### 📂 Unscoped changes

#### Other changes

- Merge tag 'v1.1.0' into develop

## 1.1.0 (2026-10-07)

*Commits from: v1.0.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v1.0.0' into develop
### 📦 vps-setup changes

#### Other changes

- 📝 add UPGRADING guide for breaking releases (#27)

## 1.0.0 (2026-10-07)

*Commits from: v0.3.0..HEAD*

### 💥 BREAKING CHANGES

- requires the renamed tomgrv/scripts (v1); zz_* and <verb>-json commands no longer exist.
### 📂 Unscoped changes

#### Features

- add Infisical to the Rancher Marketplace catalog

#### Other changes

- Merge tag 'v0.3.0' into develop
- move GitHub Actions Runner Controller to the Rancher Marketplace catalog (#16)
- 🔧 configure git identity in update-features workflow (#17)
### 📦 vps-marketplace changes

#### Features

- add cognee to the Rancher Marketplace catalog (#14)

### 📦 vps-setup changes

#### Bug Fixes

- 🔧 release with release-promote v3 and scripts v1 (#26)

#### Features

- ✨ build interactive menu with zz_menu (#22)

#### Other changes

- ♻️ use zz_persist for interactive inputs; drop root setup.sh (#20)

## 0.3.0 (2026-09-04)

*Commits from: 7a3e269cab6a9aadfc75bf5aeb6773ade89fd9ac..HEAD*

### 📂 Unscoped changes

#### Bug Fixes

- 🔧 reconcile main's vps-* rename back into develop (#11)

#### Features

- ✨ adopt shared release-promote workflow, bump devcontainer features to v8 (#10)

#### Other changes

- Add --only-<step> flags to setup.sh, document how to use them
- Add Kairos/cloud-init user-data to run setup.sh unattended on first boot
- Add PHP codename fallback and safe sudoers auto-fix for Laranode
- Add a global error trap so a failing step reports what/where instead of silently stopping
- Add cockpit-packagekit, cockpit-files, and cockpit-dockermanager install stage
- Add copy-paste install example and key-generation hints to README
- Add one-line VPS bootstrapper for fresh Ubuntu installs
- Add opt-in Laranode and Coder install steps
- ArgoCD via Helm, Tailscale-only on 7090/7093
- Document how to pass --only-*/--skip-* flags through the curl one-liner
- Document running setup.sh from a non-standard branch or fork
- Epinio via Helm, per the official install guide
- Externalize port/firewall config into network.yaml
- Fix Laranode's leftover broken ppa:ondrej/php poisoning apt system-wide
- Fix SIGPIPE (exit 141) from `tr   head -c` random password generation
- Fix Traefik-disabled detection to span k3s.service's multi-line args
- Fix and document the 'export then sudo bash' env-var gotcha
- Fix setup.sh re-run failing to update to a non-default branch
- Fix stale Apache vhost breaking apache2.service after partial-install cleanup
- Install cert-manager before Rancher, add Cockpit login, richer summary
- Make Epinio's ingress/cert-manager reuse explicit
- Merge branch 'release/0.1.0'
- Merge pull request #2 from perspikapps/claude/feature-setup-architecture-l9fuqx
- Merge tag 'v0.1.0' into develop
- Move network.yaml's port config into each feature's own package.json
- Rancher 7xxx, Coder 6xxx
- Refactor scripts with up/down actions, step dependencies, and a setup menu
- Reinstall k3s when Traefik was previously disabled by this script
- Remove Laranode/Coder; make k3s Traefik the public ingress with Let's Encrypt
- Remove Tailscale serve/funnel and the placeholder webserver
- Remove numeric prefixes from feature folder names
- Require TAILSCALE_AUTHKEY, ensure tailscaled as a service, add serve/funnel on 8052
- Restructure into one npm-workspace package per feature, add pure-sh dispatch.sh
- command not found"
- data-driven setup.sh, opt-in ArgoCD/Epinio, DRY cert-manager, doc fixes
- disable dex/notifications, raise timeout, add diagnostics
- ♻️ wire to tomgrv/scripts, restructure into one folder per script (#4)
- 🔧 add devcontainer feature
- 🔧 allow git push/tag without prompting (#5)
### 📦 release changes

#### Other changes

- 🚀 0.1.0

### 📦 vps-github-arc changes

#### Features

- add GitHub Actions Runner Controller via Helm (#3)





---
*Generated on 2026-10-08 by [tomgrv/devcontainer-features](https://github.com/tomgrv/devcontainer-features)*
