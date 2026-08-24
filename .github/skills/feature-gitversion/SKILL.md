---
name: feature-gitversion
description: Semantic versioning utilities that derive versions from git history and update tags/changelog.
---

<!-- @format -->

# gitversion

## Description

Use this feature when an agent must derive application version numbers from Git history in a consistent way.

## Commands

- `gv` - Compute version metadata from Git history.
- `bump-version` - Update version fields/files from computed version.
- `bump-tag` - Create/update version tag from release version.
- `bump-changelog` - Generate or update changelog for release context.

## Use For

- Calculating semantic versions from branch/commit state.
- Providing version metadata for build/release automation.
- Aligning local version behavior with CI versioning.

## Do Not Use For

- Manual tag/edit workflows without GitVersion involvement.
- Hook or lint orchestration (use `githooks`).

## Agent Guidance

- Use the installed GitVersion tooling as the source of truth for computed versions.
- Keep versioning logic centralized; avoid duplicating derivation rules in scripts.
- Pair with release helpers only when version flow is explicitly required.
