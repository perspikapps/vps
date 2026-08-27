<!-- @format -->

# `.agents/`

Single source of truth for every AI coding tool's configuration and guidance in this repo (Claude Code, GitHub Copilot, and any other agent that reads `.github/skills/`). Real files live here; every tool-specific conventional path is a symlink back into this directory.

**Always edit the file under `.agents/`, never a symlink.**

## Layout

| Path here        | Symlinked from          | Consumed by                   |
| ---------------- | ----------------------- | ----------------------------- |
| `skills/<name>/` | `.github/skills/<name>` | Copilot/agent-agnostic agents |

Claude Code and GitHub Copilot do not read a symlinked copy here. `.claude/hooks/configure-skills.sh sync` fetches these same skills at runtime, straight from `tomgrv/devcontainer-features:.agents/skills/`, via [`npx skills`](https://github.com/vercel-labs/skills) — run on devcontainer `postCreate` and on every Claude Code `SessionStart` (see `.claude/settings.json`).

## `ai-coding.json`

Root `ai-coding.json` is the dedicated manifest driving `configure-skills.sh sync` — it lists:

- `skills` — names under `.agents/skills/` to fetch (e.g. `caveman`, `pm/prd-draft`).
- `agents` — `npx skills` target ids to install each skill for (`claude-code`, `github-copilot`).
- `plugins` — Claude Code plugin-marketplace entries (`caveman`, `ponytail`), kept live in `.claude/settings.json`'s `enabledPlugins`/`extraKnownMarketplaces` by `configure-skills.sh sync`.

Any other installed feature that `dependsOn` `ai-coding` and ships its own `ai-coding.json` stub fragment gets it merged into this same root file (array fields are unioned) — so its skills/agents/plugins install the same way, no extra script needed beyond calling `.claude/hooks/configure-skills.sh sync` from its own `postCreateCommand`.

Skills not distributed to consumer repos (Claude Code-specific mechanisms) — `caveman-stats`, `cavecrew` — are in `.agents/skills/` only and symlinked into `.claude/skills/` but **not** into `.github/skills/` or `src/ai-coding/stubs/`.

## Adding a new distributable skill

Edit `.agents/skills/<name>/` upstream in `tomgrv/devcontainer-features` (this directory is deployed read-only into consumer repos) — see that repo's `.agents/README.md`.
