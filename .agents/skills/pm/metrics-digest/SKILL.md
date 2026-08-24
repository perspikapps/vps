---
name: pm-metrics-digest
description: >
    Produces a weekly metrics digest from usage/analytics data, comparing actuals to targets
    and flagging regressions. Use when user says "/pm-metrics-digest", "generate the weekly
    metrics digest", "summarize this week's metrics", "compare usage to targets", "flag any
    metric regressions", or provides an analytics export and asks for a digest.
---

<!-- @format -->

# Weekly Metrics Digest

## Purpose

Convert raw usage/analytics numbers into a short, scannable weekly digest that highlights what changed and what needs attention, rather than a full data dump.

## Inputs

- A metrics export (CSV/JSON/markdown table) or pasted numbers covering the period to report on.
- Target/goal values for each metric. Ask if not provided — do not invent target thresholds.
- Optional: the prior period's digest or data, to compute week-over-week deltas.

## Process

1. Parse the metrics data and identify each distinct metric and its current value.
2. Compute deltas vs. target and vs. prior period where data allows.
3. Classify each metric as on-track, at-risk, or regressed using a clear, stated threshold (e.g. more than 10% below target, or trending down for 2+ consecutive periods = regressed). State the threshold used.
4. For regressed/at-risk metrics, note plausible contributing factors only if evidence is present in the data/notes given; otherwise mark as "cause unknown, needs investigation".
5. Order the digest by severity, regressions first.

## Output

A markdown digest with: `## Summary` (one-line overall health), `## Regressions`, `## At Risk`, `## On Track` (brief), `## Methodology` (thresholds/period used). Save where the user indicates, or print inline if no save location is given.

## Notes

If an MCP connector for Google Drive/Sheets or Notion is already configured in this session, prefer pulling the live metrics from there instead of/in addition to a local export, and offer to post/save the digest into that same connector in addition to a local file.
