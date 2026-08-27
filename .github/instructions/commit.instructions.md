---
description: 'Use when writing or reviewing git commit messages, changelogs, or version bumps. Covers Conventional Commits rules, scopes, and types.'
---

<!-- @format -->

## Commit Message Format

Commit message titles must follow [Conventional Commits](https://www.conventionalcommits.org/) rules, enforced by commitlint (`package.json` → `commitlint`).

**Pattern:** `<type>(<scope>): <summary>`

- **Scope is required** — commitlint enforces `scope-enum: always`
- **Summary**: imperative mood, lowercase start, no period at the end (e.g. `add`, not `Added` or `ADDS`)
- **No emoji** in the title — added automatically by devmoji based on type

## Allowed Types

From `@commitlint/config-conventional`:

| Type       | When to use                                                  | Semver impact |
| ---------- | ------------------------------------------------------------ | ------------- |
| `feat`     | New feature or capability visible to users                   | minor bump    |
| `fix`      | Bug fix that corrects incorrect behavior                     | patch bump    |
| `perf`     | Performance improvement, no behavior change                  | patch bump    |
| `refactor` | Restructuring without adding features or fixing bugs         | no bump       |
| `test`     | Adding or updating tests only                                | no bump       |
| `docs`     | Documentation only (README, comments, changelogs)            | no bump       |
| `style`    | Formatting, whitespace, missing semicolons — no logic change | no bump       |
| `chore`    | Maintenance: tooling, config, dependency bumps               | no bump       |
| `build`    | Build system or script changes                               | no bump       |
| `ci`       | CI configuration changes                                     | no bump       |
| `revert`   | Reverts a previous commit                                    | patch bump    |

> Append `!` to type or add `BREAKING CHANGE:` in the footer for breaking changes → major bump.

## Scopes

Scopes are automatically derived from npm workspace package names via `@commitlint/config-workspace-scopes`. Valid scopes are the unscoped part of each package `name` found in the workspace paths defined by `workspaces` in root `package.json` (e.g. `@tomgrv/devcontainer-features-gitutils` → `gitutils`).

To see valid scopes at any time, run:

```bash
npm query .workspace | node -e "const d=require('fs').readFileSync(0,'utf8'); JSON.parse(d).forEach(p => console.log(p.name))"
```

**Rules for choosing a scope:**

- Use the unscoped package name of the affected workspace (strip the `@org/` prefix)
- Use the narrowest scope that accurately describes the change
- When a change spans multiple workspaces equally, pick the primary one

**Examples:**

```
feat(gitutils): add new git alias
fix(githooks): prevent double-run on post-merge
perf(common-utils): reduce script startup time
refactor(gitversion): extract bump logic into shared function
docs(gateway): document SSL setup
chore(githooks): bump @commitlint/cli to latest
feat!(pecl): remove legacy extension installer — breaking change
```
