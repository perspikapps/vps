#!/bin/sh
#
# setup.sh — one-line bootstrapper: downloads this repo to a temp dir, then
# lets the zz_use it just downloaded install the core zz_* bundle from
# there (its own local-checkout install path, resolving a bin dir and
# linking every zz_* script onto it) and discards the temp dir.
#
#   curl -fsSL https://raw.githubusercontent.com/tomgrv/scripts/main/setup.sh | sh
#
# Pin to a specific tag, branch, or commit instead of main with a
# positional arg (curl ... | sh -s -- v2) or ZZ_ORIGIN_REF=v2. Bootstrap
# from a different org/repo entirely with ZZ_ORIGIN=someorg/otherscripts.
# Both are exported for the zz_use this script hands off to (and anything
# it execs), so every zz_use call afterwards defaults to this same origin
# — "wherever this install actually came from" — rather than a hardcoded
# tomgrv/scripts:
#
#   curl -fsSL .../setup.sh | sh -s -- v2
#
# Deliberately dumb and DRY: this script owns none of the bin-dir
# resolution or linking logic itself — that's zz_use's job, and
# duplicating it here would just be a second copy to keep in sync. Once
# the core zz_* scripts (zz_use foremost) are linked, every other script,
# core or functional, resolves and installs its own further dependencies
# on demand via zz_use — from a local cache (ZZ_CACHE_DIR, default
# ~/.cache/zz_scripts) when warm, or a fresh download into that cache
# otherwise. Run `zz_update` afterwards to force a fresh download,
# bypassing the cache.
#
# Deliberately POSIX /bin/sh, no dependency on anything in this repo
# beyond a shell and curl/tar to get the temp download in place.

set -eu

export ZZ_ORIGIN="${ZZ_ORIGIN:-tomgrv/scripts}"
export ZZ_ORIGIN_REF="${1:-${ZZ_ORIGIN_REF:-main}}"
[ "$#" -gt 0 ] && shift
# The default is a separate plain assignment, not inlined into
# ${ZZ_SETUP_REPO_URL:-...}: a literal "}" inside that expansion's default
# text (from "{ORIGIN}"/"{REF}") terminates the expansion early at parse
# time, regardless of quoting — `${X:-a{REF}.b}` evaluates to `a{REF`
# with literal `.b}` appended after, not the intended default string.
# Both substitutions use "|" as the sed delimiter instead of "/": ORIGIN
# always contains "/" (org/repo), and REF can too (a branch name like
# "feature/foo") — either would break the s/// syntax with "/" as the
# delimiter.
_REPO_URL_DEFAULT='https://github.com/{ORIGIN}/archive/{REF}.tar.gz'
REPO_URL=$(printf '%s' "${ZZ_SETUP_REPO_URL:-$_REPO_URL_DEFAULT}" | sed -e "s|{ORIGIN}|${ZZ_ORIGIN}|g" -e "s|{REF}|${ZZ_ORIGIN_REF}|g")

log() { printf '\033[0;34m[zz-setup]\033[0m %s\n' "$*"; }
die() {
    printf '\033[0;31m[zz-setup]\033[0m %s\n' "$*" >&2
    exit 1
}

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v tar >/dev/null 2>&1 || die "tar is required"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

log "Downloading ${REPO_URL} to a temp dir..."
curl -fsSL "$REPO_URL" | tar -xz -C "$TMP_DIR" --strip-components=1

[ -f "$TMP_DIR/zz_use/run.sh" ] || die "Downloaded archive has no zz_use/run.sh (unexpected repo layout)"

log "Installing core zz_* scripts via the downloaded zz_use..."
sh "$TMP_DIR/zz_use/run.sh" \
    zz_use zz_update zz_colors zz_log zz_args zz_prompt zz_ask zz_input zz_bindir zz_dispatch zz_npx zz_persist zz_call

# Optional handoff: a package.json "main" field, or a root main.sh, gets
# run with the downloaded checkout as cwd-equivalent; anything else, this
# script's job (install the core bundle) is already done, so it stops.
MAIN=$(sed -n 's/^[[:space:]]*"main"[[:space:]]*:[[:space:]]*"\(.*\)"[,]*[[:space:]]*$/\1/p' "$TMP_DIR/package.json" 2>/dev/null | head -n1)
# Reject anything that could point outside $TMP_DIR (absolute paths, ".."
# segments) - "main" comes straight from a downloaded, possibly untrusted,
# repo's package.json.
case "$MAIN" in
    /* | *..*)
        log "Ignoring unsafe package.json \"main\" value: ${MAIN}"
        MAIN=""
        ;;
esac
if [ -n "$MAIN" ] && [ -f "$TMP_DIR/$MAIN" ]; then
    log "Running ${MAIN} (package.json \"main\")..."
    sh -- "$TMP_DIR/$MAIN" "$@"
elif [ -f "$TMP_DIR/main.sh" ]; then
    log "Running main.sh..."
    sh -- "$TMP_DIR/main.sh" "$@"
fi
