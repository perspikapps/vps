#!/bin/sh

# Runs lint-staged before `git commit`, so composer.json/package.json/etc.
# get validated and normalized on every commit made during a Claude Code
# session. Sessions clone the repo directly and never run the devcontainer
# postCreateCommand pipeline that would otherwise wire this up.
#
# common-utils (normalize-json/etc., used by the lint-staged rules) is
# resolved directly by package name and installed globally -- it does not
# rely on this repo's package.json declaring it as a dependency, or on npm
# workspace linking. Fires as a PreToolUse hook on Bash, filtered to
# `git commit` commands (see .claude/settings.json).

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$repo_root" || exit 0

[ -f package.json ] || exit 0

if ! command -v normalize-json >/dev/null 2>&1; then
    npm install -g @tomgrv/devcontainer-features-common-utils >&2 || {
        echo "lint-staged-precommit.sh: npm install -g common-utils failed, skipping lint-staged" >&2
        exit 0
    }
fi

npx --yes lint-staged >&2
status=$?

if [ "$status" -ne 0 ]; then
    echo "lint-staged-precommit.sh: lint-staged failed (exit $status), blocking commit" >&2
    exit 2
fi
