---
applyTo: '**/README.md'
---

<!-- @format -->

## README Conventions

Applies to every README in every repo of the family (`scripts`, `actions`, `devcontainer-features`, `vps`).

### Any README (tool, action, feature, step)

- **Consistent, coherent, simple, pragmatic.** Same section order across siblings; no repeated boilerplate; say it once.
- **Same skeleton per repo.** Title, one-line purpose, `Usage`/`Inputs`/`Options`, `Outputs`/`Environment variables`, `Dependencies`, `Tests`, `Example`. Keep what the siblings have, add what they lack.
- **Facts come from the code.** Usage and options from the script's `-h` or `zz-args` spec, inputs and outputs from `action.yml`, options and defaults from `devcontainer-feature.json`, variables from `package.json` `config`. When code and README disagree, fix the README.
- **Header and format.** First line `<!-- @format -->`; run `prettier` on the file before committing (4-space indent in lists).
- **Link, don't duplicate.** Document a tool once, in its own README; other READMEs link to it.

### Root README

- **User oriented, current usage only.** The first screen gets a reader from zero to a working install or run: what it is, a copy-paste quick start, then a catalog of what is available with one line each.
- **Exclude** past decisions, legacy flags and layouts, migration notes, "why we did it this way", internal design, test counts and release plumbing. Those belong in `UPGRADING.md`, `CHANGELOG.md` or `docs/`.
- **Keep** only what a user needs next: inputs they must provide, how to choose or remove parts, how to verify it worked, troubleshooting, and a short Contributing section (how to run tests, which branch to target).
- **Order:** purpose, quick start, catalog, how-to sections, troubleshooting, contributing, license.
