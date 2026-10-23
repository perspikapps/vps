---
applyTo: '**/run.sh'
description: 'POSIX sh conventions for the zz-* and functional scripts: file layout, comments, functions, flow, indentation and naming.'
---

<!-- @format -->

## Shell Scripts

### Comment every high-level block

Every high-level code block (an argument parse, a parameter check, a function, a `# --- section` of the main flow, a loop or branch that is a step of the script) gets a comment saying what it does and, when not obvious, why. One or two lines. Do not comment single statements.

### Layout

Order every `run.sh` the same way:

1. **Header** – usage comment, then `. zz-colors` (and `set -e` if used).
2. **Default `zz-args`** – the `eval "$(zz-args ... <<help ... help)"` block declaring every option and positional. No hand-written `getopts` or `case "$1"` loops.
3. **Parameters handling** – validate the parsed values, apply defaults, derive paths and names. Fail early with `zz-log e` and a usage line.
4. **Function definitions** – all helpers, each with a comment.
5. **Code blocks** – the main flow, one commented `# --- step` block at a time.

A script whose later arguments depend on earlier work (a second `zz-args` call after discovery) keeps the first three parts at the top and says why in a comment.

### Reuse before writing

Prompt with `zz-prompt` (confirmations: `zz-prompt -c Yn "Q?"`; secrets: `zz-prompt -s`, persisted with `zz-persist -s`), install with `zz-install`, pick a bin dir with `zz-bindir`, fetch repos with `zz-fetch`, choose with `zz-menu`.

Never write inline `apt-get`/`apk`/`sudo` branching. Install system packages with `zz-use zz-install` then `zz-install <pkg> apk=<alt> brew=<alt>` (see `src/gitutils/install-gitflow.sh`).

### Source only `zz-*` scripts

A managed script (anything installed or run through `zz-use`/`zz-setup`) sources nothing but `zz-*` scripts: `. zz-colors`. Shared logic never travels through `.`, because a sourced file shares the caller's shell (variables, `set -e`, traps, `$0`) and breaks the moment the two drift apart. Put it in a command on `PATH` and call it (`vps-network public-ip`, `zz-persist -r KEY`), with its own `zz-use` line and arguments. Two things may still be sourced: a data file in shell syntax that is not a script of the repo (`/etc/os-release`, a settings file the user provides, read under a comment saying so), and a `config.functions` step, which `zz-setup` sources (see below).

### Logging

- Script messages go through `zz-log <level>`; the caller sets `ZZ_LOG_STEP` (current step) and raises `ZZ_LOG_INDENT` by 2 for a nested child.
- What a command prints (git, an installer) is operation output: forward it with `... | zz-log o` or `out=$(cmd 2>&1) || rc=$?`.

### POSIX `sh` only

Write `#!/bin/sh` scripts that run under dash and busybox. No bashisms:

- Tests: `[ ]` with `=`, never `[[ ]]`, `==` or `test` mixed with `[ ]`. Quote every expansion: `"$var"`.
- Arithmetic: `$((a + 1))`, never `expr`.
- Input: pipe or here-doc (`printf '%s\n' "$json" | jq …`), never `<<<`.
- No arrays, `${var//x/y}`, `$'…'`, `PIPESTATUS`, `source` or `function`. Use `sed`/`tr`, `.`, and a captured `$?` instead.
- `local` is allowed (dash and busybox support it); declare every function variable with it.

### Functions

- One job per function, named for what it answers: `is_*` returns a status, `get_*` prints one value.
- Document each parameter with a trailing comment, marking it mandatory or optional; default with `${1:-.}`.
- Take input on stdin when the function is a filter, so it composes in a pipe.
- stdout carries data only. All logging goes through `zz-log` (stderr).

### Flow

- Fail at the point of detection with a guard clause: `zz-log e "<the specific thing>" && exit 1`.
- Choose between variants with `case`, using `continue` to skip a missing one. Do not chain `if`/`elif` over the same key.
- Resolve a value from several sources as a flat cascade, one `if [ -n "$opt" ] && [ -z "$value" ]` step per source, in priority order, and log which source won.
- Cache expensive results by content hash, and only when the caller opts in.

### Indentation and spacing

- Indent with 4 spaces, never tabs. This is the repo's prettier setting (`tabWidth: 4`, `useTabs: false`, `singleQuote`); run `npx prettier --write` on edited scripts and keep what it produces.
- In a `case`, align each pattern with `case` and indent its body one level. End a branch with `;;` at the body's indent.
- Keep a one-line body on one line when it stays short: `is_json() { jq empty 2>/dev/null; }`. Open a block as soon as it holds a second statement.
- Leave one blank line between functions, between `# --- step` blocks, and around each top-level `if`, `for`, `while` or `case`. Never leave two in a row.
- Group a function's `local` lines together and follow them with one blank line. Do not open a short function with a blank line.
- Inside a `case`, leave one blank line after `case … in` and after each pattern line when the body has more than one statement.
- Write the `zz-args` here-doc as plain `<<help` with a spaces-only body and an unindented closing `help` (no `<<-`, no tabs). Keep its help text aligned in columns: short flag, long name, variable, description.
- Wrap a pipeline at `|` only past 100 characters, and indent the continuation one level.

### Naming

- Script folders are `kebab-case`, `<domain>-<action>` (`json-validate`, `git-fix-up`). Shared helpers take the `zz-` prefix. The entry point is always `run.sh`.
- Functions are `snake_case`, verb first: `is_*` and `has_*` answer yes or no, `get_*` prints a value, other verbs act (`install_package`). A helper that is not the script's purpose may take a leading `_` (`_collect`).
- A function that mirrors a name from the domain keeps that name's case: `oneOf_rule` matches the JSON Schema keyword `oneOf`.
- Variables are lowercase and short, named for what they hold: a singular noun for one value (`json`, `schema`, `path`), a plural for a list (`props`, `items`). Say what a flag means, not how it is stored: `allow`, not `flag1`.
- An option's long name equals its variable (`-s schema` fills `$schema`). Its short flag is the first letter, or the next free one.
- Colour variables from `zz-colors` are Capitalised (`Yellow`, `None`). Environment variables are `UPPER_SNAKE` with the `ZZ_` prefix (`ZZ_LOG_STEP`).
- Avoid abbreviations unless they are standard (`dir`, `tmp`, `url`). Do not introduce a second name for something that already has one in the script.

### zz-setup compatibility

A repository run by `zz-setup <org>/<repo>` is a set of workspaces, one folder per step. A step's `run.sh` follows the rules above and also these:

- **Runnable step**: the folder holds `package.json` and `run.sh`. `package.json` declares `bin: {"<folder>": "run.sh"}` and `engines: {"zz-setup": "*"}`; without `engines.zz-setup` the folder is a library, never proposed as a step. The folder is a root `workspaces` entry. Order comes from `config.order`, never from the folder name.
- **Actions**: set `config.functions: true` and define `up()`, `down()` and `summary()` (plus any extra action, called with `zz-setup <repo> -o <step> -a <action>`); `zz-setup` sources the bin from its own directory and calls the one asked, so the file has no dispatch code and is not run on its own (`zz-setup ./ -o <step>` runs a local checkout). `config.summary: true` makes `zz-setup` print the step's `summary()` after a run. Without `config.functions` the bin is run with `up` or `down` as its first argument. `up` and `down` are idempotent: a re-run repairs, never fails on what already exists. `down` undoes only what `up` created. `zz-setup` runs `down` steps in reverse order, then `up` steps in order.
- **Inputs**: declare every variable in `config.inputs` (`description`, `required`, `default`, `secret`). Read it from the environment; `zz-setup` resolves environment, then env file, then default. A step never prompts: it runs without a terminal and `sudo` drops the environment. Document each input in the step README.
- **Secrets**: generate once, then reuse. Store with `zz-persist -s` (owner-only env file), never echo to a log line other than the final summary, and mark the input `"secret": true`.
- **Dependencies**: list other steps in `dependencies` or `peerDependencies`; `zz-setup` enables them. Steps that cannot share a host name each other in `config.conflicts`. Shared logic lives in scripts that are called, never sourced (see "Source only `zz-*` scripts"): a folder with a `bin` and no `engines.zz-setup` is a script, not a step, and a step reaches it by path (`$(dirname "$0")/../<script>/run.sh`).
- **No self-bootstrap**: a step never installs `zz-setup` or `zz-use`. It starts with `set -eu`, then one `zz-use` line for the tools it calls, then `. zz-colors`.
- **Host requirements**: declare them in `config.requires` (`{"root": true, "os": "ubuntu"}`); `zz-setup` checks them with `zz-require` before the first selected step runs. A step does not test for root or the OS itself.
- **Local state**: derive paths from `$0` (`zz-setup` sources the bin from its own directory, so `$0` is `./run.sh`), not from `$PWD` or a hard-coded checkout path; `zz-setup` may run a local path in place or a fresh clone.
- **Check**: `dash -n run.sh` passes, and the step has a `test.bats` that covers its syntax and shape.
