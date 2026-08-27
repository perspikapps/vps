---
name: feature-common-utils
description: Shared shell utilities for JSON validation, normalization, and reusable zz_* helper scripts.
---

<!-- @format -->

# common-utils

## Description

Use this feature as a shared utility layer for shell-based automation across features (`jq`, `dos2unix`, and `zz_*` helper scripts).

## Commands

- `validate-json [options] <json>` - Validate JSON against a schema.
- `normalize-json [options] <json>` - Normalize JSON order/format using schema rules.
- `zz_dist [options]` - Copy `zz_*` helpers to a target directory.
- `zz_args` - Parse command-line arguments in shell scripts.
- `zz_log` - Emit structured/colorized shell logs.
- `zz_json` - Read or manipulate JSON from shell scripts.

## Use For

- JSON validation/normalization workflows (`validate-json`, `normalize-json`).
- Shell scripting with standardized logging, argument parsing, and prompts (`zz_log`, `zz_args`, `zz_ask`).
- Distributing shared helper scripts into project folders (`zz_dist`).

## Do Not Use For

- Feature-specific business logic.
- Git workflow automation (use `gitutils` or `githooks`).

## Agent Guidance

- Reuse existing `zz_*` scripts before adding new helpers.
- Prefer `normalize-json`/`validate-json` in lint pipelines for schema-safe edits.
- Keep automation generic and composable for cross-feature reuse.
