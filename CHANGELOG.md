# Changelog

## 4.10.0 (2026-10-28)

*Commits from: v4.9.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v4.9.0' into develop
### 📦 app-coder changes

#### Features

- ✨ track local registry as SYSTEM_REGISTRY_URL, drop ghcr.io default (#67)

### 📦 vps-setup changes

#### Other changes

- 📚️ 📝 refresh deployed hosts with zz-use -f, zz-update is removed (#69)

## 4.9.0 (2026-10-28)

*Commits from: v4.8.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v4.8.0' into develop
### 📦 vps-access changes

#### Features

- ✨ menus on the common row grammar, coherent input descriptions (#66)

## 4.8.0 (2026-10-27)

*Commits from: v4.7.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v4.7.0' into develop
### 📦 vps-network changes

#### Features

- ✨ public/internal access, vps/svc/app steps, shared helpers (#65)

## 4.7.0 (2026-10-25)

*Commits from: v4.6.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v4.6.0' into develop
### 📦 vps changes

#### Other changes

- 📝 add cloud-init README (#61)

### 📦 vps-setup changes

#### Other changes

- 📚️ 📝 rewrite root README around current usage (#62)

### 📦 vps-system changes

#### Features

- ✨ support dnf and zypper alongside apt (#63)

## 4.6.0 (2026-10-23)

*Commits from: v4.5.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v4.5.0' into develop
### 📦 vps-network changes

#### Other changes

- ♻️ list steps with ws-list instead of zz-workspaces (#59)

## 4.5.0 (2026-10-23)

*Commits from: v4.4.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v4.4.0' into develop
### 📦 vps-setup changes

#### Other changes

- ♻️ remove config.functions; steps are plain scripts run with up, down or summary (#60)

## 4.4.0 (2026-10-23)

*Commits from: v4.3.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v4.3.0' into develop
### 📦 vps-rancher changes

#### Features

- ✨ serve the dashboard through Traefik; POSIX sh and helm/ yaml for every step (#57)

## 4.3.0 (2026-10-19)

*Commits from: v4.2.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v4.2.0' into develop
### 📦 vps-security changes

#### Bug Fixes

- 🐛 restrict private ufw rules to the private IP (#55)

## 4.2.0 (2026-10-19)

*Commits from: v4.1.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v4.1.0' into develop
### 📦 vps-marketplace changes

#### Bug Fixes

- create .cr-index before cr index so the Helm index is pushed (#53)

## 4.1.0 (2026-10-19)

*Commits from: v4.0.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v4.0.0' into develop
### 📦 vps-marketplace changes

#### Bug Fixes

- add the infisical Helm repo so every chart can be packaged (#52)

## 4.0.0 (2026-10-19)

*Commits from: v3.0.0..HEAD*

### 💥 BREAKING CHANGES

- vps-dockermanager is removed (folder, --only/--down flags,
### 📂 Unscoped changes

#### Other changes

- Merge tag 'v3.0.0' into develop
### 📦 ci changes

#### Bug Fixes

- bootstrap gh-pages and release all charts so the Helm repo index is published (#48)

### 📦 vps-cloudflare changes

#### Features

- ✨ opt-in Cloudflare Tunnel, vps-coder platform, wildcard DNS (#50)

### 📦 vps-marketplace changes

#### Features

- ✨ serve catalog apps on server-domain subdomains via ClusterIP + Ingress (#49)

### 📦 vps-security changes

#### Bug Fixes

- keep private ports off the public interface for k3s and Docker

## 3.0.0 (2026-10-17)

*Commits from: v2.11.0..HEAD*

### 💥 BREAKING CHANGES

- 💥 ♻️ migrate package.json vps key to engines.zz-setup (#45)
### 📂 Unscoped changes

#### Other changes

- Merge tag 'v2.11.0' into develop
- update features (#34)

## 2.11.0 (2026-10-15)

*Commits from: v2.10.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v2.10.0' into develop
### 📦 vps-setup changes

#### Other changes

- 👷 pin actions to v5, scripts to v3 and features to v11 (#44)

## 2.10.0 (2026-10-15)

*Commits from: v2.9.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v2.9.0' into develop
### 📦 rancher changes

#### Features

- add RANCHER_CHART_REPO_URL input for SUSE Prime (#41)

## 2.9.0 (2026-10-15)

*Commits from: v2.8.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v2.8.0' into develop
### 📦 vps-common changes

#### Other changes

- store credentials with zz-persist, share apt_purge and cockpit_refresh (#43)

## 2.8.0 (2026-10-15)

*Commits from: v2.7.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v2.7.0' into develop
### 📦 vps-common changes

#### Other changes

- shared root check, port override, download_run and per-step summary (#42)

### 📦 vps-security changes

#### Other changes

- read the private interface persisted by vps-tailscale instead of hard-coding tailscale0 (#37)

## 2.7.0 (2026-10-14)

*Commits from: v2.6.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v2.6.0' into develop
### 📦 vps-rancher changes

#### Bug Fixes

- 🐛 recreate an already-rebound Service before helm upgrades (#40)

## 2.6.0 (2026-10-14)

*Commits from: v2.5.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v2.5.0' into develop
### 📦 vps-setup changes

#### Bug Fixes

- 🐛 refresh the cached vps-common and report a stale one clearly (#39)

## 2.5.0 (2026-10-14)

*Commits from: v2.4.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v2.4.0' into develop
### 📦 vps-rancher changes

#### Bug Fixes

- 🐛 fix the install hang and report progress during long waits (#38)

## 2.4.0 (2026-10-14)

*Commits from: v2.3.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v2.3.0' into develop
### 📦 vps-rancher changes

#### Bug Fixes

- 🐛 pass hostname and bootstrap password as strings via a values file (#36)

## 2.3.0 (2026-10-14)

*Commits from: v2.2.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v2.2.0' into develop
### 📦 vps-setup changes

#### Other changes

- ♻️ become a thin wrapper around zz-setup (#35)

## 2.2.0 (2026-10-13)

*Commits from: v2.1.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v2.1.0' into develop
- update features (#31)
### 📦 vps-security changes

#### Bug Fixes

- warn instead of failing when ssh.service is not active (#33)

### 📦 vps-setup changes

#### Bug Fixes

- 🐛 let update-features push workflow changes with an optional token (#30)
- 🐛 sync package-lock.json so npm ci succeeds (#32)

## 2.1.0 (2026-10-08)

*Commits from: v2.0.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v2.0.0' into develop
### 📦 vps-setup changes

#### Other changes

- 👷 run update-features every night instead of every week (#29)

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
*Generated on 2026-10-28 by [tomgrv/devcontainer-features](https://github.com/tomgrv/devcontainer-features)*
