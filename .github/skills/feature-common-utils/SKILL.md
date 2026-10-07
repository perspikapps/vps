---
name: feature-common-utils
description: Shared shell utilities for JSON validation, normalization, and reusable zz-* helper scripts.
---

<!-- @format -->

# common-utils

## Description

Use this feature as a shared utility layer for shell-based automation across features (`jq`, `dos2unix`, and `zz-*` helper scripts).

## Commands

- `json-validate [options] <json>` - Validate JSON against a schema.
- `json-normalize [options] <json>` - Normalize JSON order/format using schema rules.
- `zz-dist [options]` - Copy `zz-*` helpers to a target directory.
- `zz-args` - Parse command-line arguments in shell scripts.
- `zz-log` - Emit structured/colorized shell logs.
- `zz-json` - Read or manipulate JSON from shell scripts.

## Use For

- JSON validation/normalization workflows (`json-validate`, `json-normalize`).
- Shell scripting with standardized logging, argument parsing, and prompts (`zz-log`, `zz-args`, `zz-ask`).
- Distributing shared helper scripts into project folders (`zz-dist`).

## Do Not Use For

- Feature-specific business logic.
- Git workflow automation (use `gitutils` or `githooks`).

## Agent Guidance

- Reuse existing `zz-*` scripts before adding new helpers.
- Prefer `json-normalize`/`json-validate` in lint pipelines for schema-safe edits.
- Keep automation generic and composable for cross-feature reuse.
