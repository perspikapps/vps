---
name: pm-release-notes
description: >
    Generates user-facing release notes from closed tickets/PRs for a sprint or release, written
    in brand voice. Use when user says "/pm-release-notes", "generate release notes", "draft
    release notes for this sprint", "write the changelog for users", "what shipped this release",
    or asks for release notes covering a date range, milestone, or set of closed issues/PRs.
---

<!-- @format -->

# Release Notes Generator

## Purpose

Translate closed, internally-worded tickets/PRs into concise, user-facing release notes — distinct from a technical, commit-message-driven changelog.

## Inputs

- A scope to cover: a date range, milestone/tag, or explicit list of issue/PR numbers.
- The closed tickets/PRs themselves, obtained via `gh issue list --state closed` / `gh pr list --state merged` (with appropriate `--search`/date filters) if no local export is given, or a local export file if the user provides one.
- Optional: a brand-voice guide or examples of past user-facing release notes to match tone. If nothing else is given, existing repo docs (README, CHANGELOG) may offer tone cues, but flag that they are likely too technical to reuse verbatim.

## Process

1. Resolve scope to a concrete list of closed tickets/merged PRs, using `gh` CLI read commands when the user hasn't supplied a file.
2. Discard purely internal items (refactors, CI/test-only changes, dependency bumps) unless they have user-visible impact.
3. Rewrite each remaining item from implementation language into a benefit/outcome statement a non-technical user would understand.
4. Group items into categories: New, Improved, Fixed.
5. Keep each entry to one or two sentences.
6. Match the requested brand voice, or default to a neutral, friendly, concise tone if none is given — state which tone was used.

## Output

Markdown release notes with a title/date heading, then `## New`, `## Improved`, `## Fixed` sections (omit empty sections), each a bullet list of one-line user-facing entries, optionally linking back to the source issue/PR. Save where the user indicates (e.g. alongside an existing `CHANGELOG.md` if asked).

## Notes

If an MCP connector for Linear, Jira, Notion, or Slack is already configured in this session, prefer pulling closed work from those systems instead of/in addition to `gh`/git history, and offer to publish the notes into a connected destination (e.g. a Notion page, a Slack announcement draft) in addition to a local file.
