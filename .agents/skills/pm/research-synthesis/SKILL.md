---
name: pm-research-synthesis
description: >
    Synthesizes raw user research (interview notes, call transcripts, survey responses) into
    a structured insight report with themes, representative quotes, and opportunity areas.
    Use when user says "/pm-research-synthesis", "synthesize research", "synthesize these
    interview notes", "summarize user research", "find themes in these notes", or points to a
    folder/file of research notes and asks for insights.
---

<!-- @format -->

# Research Synthesis

## Purpose

Turn unstructured qualitative research into a decision-ready insight report. Reduce a pile of interview notes or transcripts into themes a product manager can act on. This is not a transcription or note-taking tool — the input is assumed to already be captured.

## Inputs

- A folder or list of files containing raw notes/transcripts. Ask the user for the path if not given.
- Optional: a specific research question or product area to focus on.
- Optional: prior insight reports, to avoid duplicating already-known themes.

## Process

1. Read every file in the pointed-to folder/path.
2. Extract verbatim or near-verbatim quotes, tagged with their source file/participant.
3. Cluster quotes into recurring themes, naming each theme concisely.
4. For each theme, identify an opportunity area — a candidate problem/feature direction, not a solution.
5. Note contradictions or minority viewpoints separately rather than discarding them.
6. Flag any notes that were too sparse or ambiguous to use.

## Output

A markdown report with:

- `## Themes` — each theme's name, supporting quotes with source attribution, and how many participants raised it.
- `## Opportunity Areas` — grouped by theme.
- `## Open Questions / Contradictions`

Save the report to a path the user specifies, or ask where to save it if unclear.

## Notes

If an MCP connector for Notion, Google Drive, or Gmail is already configured in this session, prefer reading research notes from there instead of/in addition to local files, and offer to write the resulting report back into the same connector (e.g. a new Notion page).
