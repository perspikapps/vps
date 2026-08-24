---
name: pm-roadmap-brief
description: >
    Builds a scored, ranked roadmap prioritization brief from a list of backlog items, cross-
    referenced against stated strategy/OKRs. Use when user says "/pm-roadmap-brief", "prioritize
    the roadmap", "rank the backlog", "build a roadmap brief", "score these backlog items
    against our OKRs", or provides a backlog export and strategy doc and asks what to build next.
---

<!-- @format -->

# Roadmap Prioritization Brief

## Purpose

Convert a raw backlog list plus a strategy/OKR statement into a ranked, justified roadmap. Make prioritization rationale explicit and auditable rather than a gut-feel list.

## Inputs

- A backlog file/export (CSV, markdown table, or plain list of items with at least a title and short description).
- A strategy or OKR document/text. Ask for it if not supplied — do not invent company goals.
- Optional: a scoring framework preference (RICE, ICE, value/effort). Propose one if none is given.

## Process

1. Parse the backlog into discrete items.
2. Read the strategy/OKR input and extract the goals it implies.
3. Score each backlog item against the chosen framework's dimensions, explicitly tying each score to a specific OKR/strategy line where possible.
4. Compute a total/ranked score per item.
5. Sort items descending by score.
6. Call out items that score high but map to no stated OKR (potential scope creep), and OKRs with no backlog coverage (gaps).

## Output

A markdown brief with:

- `## Ranked Roadmap` — table of rank, item, score, key rationale.
- `## Scoring Methodology` — the framework and dimension weights used.
- `## Gaps & Risks` — OKRs without coverage, high scorers without strategy tie-in.

Save where the user indicates, or ask if unclear.

## Notes

If an MCP connector for Linear, Jira, or Notion is already configured in this session, prefer pulling the live backlog/OKRs from there instead of/in addition to a local export, and offer to write the resulting priority/score back to each ticket where the connector supports it.
