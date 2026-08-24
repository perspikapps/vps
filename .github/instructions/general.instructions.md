---
applyTo: '**'
---

<!-- @format -->

## Minimal Changes Discipline

Make the smallest possible change to address the specific request. Do not modify files unrelated to the task.

- **Package files** (`package.json`, `package-lock.json`): only modify if explicitly required for the task.
- **Build artifacts and symlinks**: do not commit unless they are the direct target of the request.
- **Repository setup** (symlinks, environment bootstrapping): use temporarily for development/testing only; do not commit.
- **Infrastructure changes**: avoid unless specifically requested.

When working on any task:

1. Identify the **exact files** that need to change.
2. Change **only** those files.
3. Use temporary local setup for testing; revert any unrelated side effects before committing.
4. Focus on the **specific feature or fix** requested, not general improvements.
