---
name: feature-githooks
description: Git hook automation for commit quality gates, commit message validation, and staged-file linting.
---

<!-- @format -->

# githooks

## Description

Use this feature when an agent needs consistent local Git quality gates and commit workflow automation.

## Commands

- `git commit` - Triggers `pre-commit`, `prepare-commit-msg`, and `commit-msg` hooks.
- `git push` - Triggers `pre-push` validations before remote update.
- `git checkout <branch>` - Triggers `post-checkout` hook operations.
- `git merge` - Triggers `post-merge` hook operations.
- `commitlint --edit <file>` - Validate a commit message against commitlint rules.
- `lint-staged` - Run configured lint/format commands on staged files.

## Use For

- Enforcing commit message standards (`commitlint`, `commitizen`).
- Running pre-commit checks/linting on staged files.
- Validating branch naming and push readiness.
- Keeping dependencies aligned after checkout/merge hooks.

## Do Not Use For

- Repository history rewriting (use `gitutils`).
- Version calculation from history (use `gitversion`).

## Agent Guidance

- Treat hooks as the default guardrails for local commits.
- Update hook-related package snippets/scripts instead of introducing duplicate checks.
- When failures occur, fix the underlying issue and rerun the same hook path.
