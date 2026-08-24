---
name: feature-gitutils
description: Advanced git aliases and workflows for branch integration, history maintenance, and release flows.
---

<!-- @format -->

# gitutils

## Description

Use this feature for advanced Git operations, interactive repository maintenance, and git-flow shortcuts.

## Commands

- `git align` - Align current branch with its remote tracking branch.
- `git integrate` - Integrate remote modifications into current branch.
- `git fixup [--force|<commit>]` - Amend a target commit and rebase history.
- `git getcommit [--force|<commit>]` - Resolve/select commit target for fixup.
- `git fix date [options] [<commit>]` - Rewrite commit times with scheduling rules.
- `git fix blanks [-d]` - Drop tracked text-file edits made only of whitespace, blanks, and quote/slash swaps.
- `git forall <command>` - Execute a command for repository files.
- `git release-beta` - Start a Git Flow release branch.
- `git release-hotfix` - Start a Git Flow hotfix branch.
- `git release-prod` - Finish release/hotfix flow for production.
- `git unset <prefix> [--local|--global|--system]` - Remove git config keys by prefix.

## Use For

- Branch/rebase alignment and integration tasks.
- Commit cleanup/fixup workflows.
- Release branch shortcuts (`beta`, `hfix`, `prod`).
- Batch repository operations and helper aliases.

## Do Not Use For

- Commit policy enforcement hooks (use `githooks`).
- Semantic version calculation (use `gitversion`).

## Agent Guidance

- Prefer built-in aliases/utilities before crafting raw multi-step Git commands.
- For history-rewrite actions, use explicit/force flags only when requested.
- Keep operations scoped and reversible where possible.
