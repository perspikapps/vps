#!/bin/sh

### Install git hooks alongside husky: make sure the git-hook-<name>
### commands the .husky/<hook> wrappers delegate to are on PATH, then let
### husky point core.hooksPath at .husky/_. Idempotent and never fails its
### caller, so it is safe from every entry point:
###   - npm `prepare` lifecycle script (plain `npm install`, any machine)
###   - configure-husky.sh (devcontainer postCreate, via feature-configure)
###   - Claude Code SessionStart hook (.claude/settings.json) - cloud/web
###     sessions clone the repo directly and run neither of the above
###   - the .husky/<hook> wrappers themselves (sourced), as a last resort
### Sourced by the wrappers, so no `exit` here: everything runs in a
### subshell, and only the PATH export below leaks into the caller.

### Appended, not prepended: never shadow the caller's own node/npm/etc.
if [ "${HUSKY:-}" != "0" ]; then
    export PATH="$PATH:${INSTALL_BIN_DIR:-/usr/local/bin}:$HOME/.local/bin"
fi

(
    [ "${HUSKY:-}" = "0" ] && exit 0
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
    cd "$repo_root" || exit 0

    ### Bootstrap zz-use from tomgrv/scripts when missing (same bootstrap
    ### as the githooks feature's install.sh)
    if ! command -v zz-use >/dev/null 2>&1; then
        _zz_setup_tmp=$(mktemp) || exit 0
        if curl -fsSL "${ZZ_SCRIPTS_SETUP_URL:-https://raw.githubusercontent.com/tomgrv/scripts/main/setup.sh}" -o "$_zz_setup_tmp" &&
            sh "$_zz_setup_tmp" >&2; then
            :
        else
            rm -f "$_zz_setup_tmp"
            echo ".husky/install.sh: zz-use bootstrap failed, git hooks not installed" >&2
            exit 0
        fi
        rm -f "$_zz_setup_tmp"
    fi

    zz-use git-hook-commitmsg git-hook-installplugins git-hook-postcheckout \
        git-hook-postmerge git-hook-precommit git-hook-preparecommitmsg \
        git-hook-prepush >&2 || echo ".husky/install.sh: some git-hook-* commands failed to install" >&2

    ### json-normalize, run by the lint-staged config on staged *.json
    ### (stubs/_lint-staged.package.json), comes from common-utils
    if ! command -v json-normalize >/dev/null 2>&1; then
        npm install -g @tomgrv/devcontainer-features-common-utils >&2 ||
            echo ".husky/install.sh: npm install -g common-utils failed" >&2
    fi

    ### husky from node_modules/.bin in an npm script, npx otherwise
    if [ "$(git config core.hooksPath)" != ".husky/_" ]; then
        if command -v husky >/dev/null 2>&1; then husky; else npx --yes husky; fi >&2 ||
            echo ".husky/install.sh: husky init failed" >&2
    fi

    ### Claude Code: persist PATH for the session's later Bash calls (and
    ### the git hooks they trigger)
    if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
        line="export PATH=\"\$PATH:${INSTALL_BIN_DIR:-/usr/local/bin}:\$HOME/.local/bin\""
        grep -qxF "$line" "$CLAUDE_ENV_FILE" 2>/dev/null || echo "$line" >>"$CLAUDE_ENV_FILE"
    fi
    exit 0
)
