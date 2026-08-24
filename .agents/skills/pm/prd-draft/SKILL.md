---
name: pm-prd-draft
description: >
    Drafts a structured PRD (problem, users, success metrics, scope, non-goals, open questions)
    from a feature request, ticket, or rough description. Use when user says "/pm-prd-draft",
    "draft a PRD", "write a PRD for this feature", "turn this ticket into a spec", "create a
    product requirements doc", or points to a feature request/ticket and asks for a spec.
---

<!-- @format -->

# PRD Auto-Drafter

## Purpose

Turn an informal feature request or ticket into a structured, reviewable PRD. Surface missing information as explicit open questions rather than guessing silently.

## Inputs

- The feature request itself: a ticket file/export, a pasted description, or a GitHub issue reference/number.
- Optional: related context (existing PRDs, design docs, prior research insight reports) to ground scope decisions.
- Optional: a PRD template the team already uses — check the repo's `docs/` directory (or similar) before assuming a default structure.

## Process

1. Read the request and any linked/attached context fully before drafting.
2. Restate the problem in the user's own terms, distinct from the proposed solution.
3. Identify target users/personas explicitly, even if only inferred — flag inferred ones as assumptions.
4. Propose 1-3 measurable success metrics tied to the problem statement.
5. Define scope as concrete inclusions, and a separate non-goals list of plausible-but-excluded work.
6. List every open question/decision still needed rather than resolving it unilaterally.
7. If the `gh` CLI is available and the request references a GitHub issue number, fetch the issue body/comments for context.

## Output

A markdown PRD with: `## Problem`, `## Users`, `## Success Metrics`, `## Scope`, `## Non-Goals`, `## Open Questions`. If drafted from a GitHub issue, include a back-link to the issue URL at the top. Save where the user indicates.

## Notes

If an MCP connector for Notion, Linear, Jira, or Google Drive is already configured in this session, prefer reading the originating ticket/request from there, and offer to create/attach the PRD there too instead of/in addition to a local markdown file.
