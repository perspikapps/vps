<!-- @format -->

---

name: commit-naming
description: Generate, review, or improve git commit messages for this repository. Use this skill whenever the user asks for a commit message, commit title, PR-sized commit breakdown, or naming suggestions for a change.
argument-hint: [changed files or summary of changes]
user-invocable: true

---

# Commit Naming

Use this skill whenever:

- the user asks for a commit message
- a change needs to be summarized as a Conventional Commit
- a diff, PR, or file list needs commit naming help
- a commit message should be reviewed or corrected

## Objective

All commit suggestions **must** follow the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/#specification) specification with [devmoji](https://github.com/folke/devmoji#default-devmoji-reference). This ensures a consistent commit history and enables automated changelog generation.

### Format

```
<type>[optional scope]: <devmoji icon> <description>

[optional body]

[optional footer(s)]
```

### Allowed Types

| Type       | When to use                              | Emoji |
| ---------- | ---------------------------------------- | ----- |
| `feat`     | A new feature                            | `✨`  |
| `fix`      | A bug fix                                | `🐛`  |
| `docs`     | Documentation-only changes               | `📚`  |
| `style`    | Formatting, whitespace (no logic change) | `🎨`  |
| `refactor` | Code restructure without feature/fix     | `♻️`  |
| `perf`     | Performance improvement                  | `⚡`  |
| `test`     | Adding or updating tests                 | `🚨`  |
| `chore`    | Build process, dependencies, tooling     | `🔧`  |
| `ci`       | CI/CD configuration changes              | `👷`  |
| `revert`   | Reverts a previous commit                | `⏪`  |

### Rules

- The **type** is mandatory and must be lowercase.
- The **description** must be in the imperative mood, lowercase, must **not** end with a period.
    - ✅ `fix(auth): handle expired token gracefully`
    - ❌ `Fixed the auth bug.`
- fix: a commit of the type fix patches a bug in your codebase (this correlates with PATCH in Semantic Versioning).
- feat: a commit of the type feat introduces a new feature to the codebase (this correlates with MINOR in Semantic Versioning).
- Breaking changes must append `!` after the type/scope and include a `BREAKING CHANGE:` footer.Introduces a breaking API change (correlating with MAJOR in Semantic Versioning).
    - Example: `feat!: drop support for Node 14`
- **Every** code suggestion that would result in a commit must include a Conventional Commit-compliant
  commit message proposal in the review comment.
- For stub-only or tooling-only changes, default to `chore` unless the change introduces new user-facing capability.
- If a change is documentation-only, always prefer `docs`.
- **Scope** should be sub-package or module name that can be deducted from the code changes and pointing to a sub package or module (eg: npm **workspaces**, composer local packages). If the change is not specific to a sub-package or module, the scope can be omitted.
- footers other than `BREAKING CHANGE`: <description> may be provided and follow a convention similar to git trailer format
- footers may also include references to issues closed by the commit, using the format `Closes #123` or `Fixes #123`
- title/body/footer/ must be less than 72 characters wide

## Code Style

- Prefer clarity over cleverness.
- Keep functions small and single-purpose.
- Document public APIs and non-obvious logic.
- Prefer early returns over deeply nested conditionals.
- Flag any code that could be simplified, extracted, or made more idiomatic — and always
  provide the simplified version as a suggestion block.

## Validation checklist

Before returning a commit message, verify:

- valid Conventional Commit type
- scope is useful and relevant, or omitted
- correct devmoji for the selected type
- lowercase imperative description
- no trailing period
- concise and specific wording
