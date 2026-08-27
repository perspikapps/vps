#!/bin/sh
#
# setup.sh — installs zz_use (from https://github.com/tomgrv/scripts) onto
# PATH, so this repo's own scripts can rely on it instead of each one
# embedding the tomgrv/scripts bootstrap directly:
#
#   command -v zz_use >/dev/null 2>&1 || curl -fsSL .../vps/main/setup.sh | sh
#
# A thin wrapper, deliberately: zz_use itself isn't this repo's script —
# it lives in tomgrv/scripts, and duplicating its own setup.sh here would
# just be a second copy to keep in sync (the same reasoning tomgrv/scripts'
# own setup.sh gives for delegating bin-dir/linking logic to zz_use rather
# than reimplementing it). This script's only job is picking the right
# tomgrv/scripts URL/ref and handing off.
#
# Pin to a specific tomgrv/scripts tag, branch, or commit instead of main
# with ZZ_SCRIPTS_REF, or bootstrap from a fork entirely with
# ZZ_SCRIPTS_SETUP_URL (the full setup.sh URL, not just an origin/ref):
#
#   curl -fsSL .../vps/main/setup.sh | ZZ_SCRIPTS_REF=v2 sh
#
# Once zz_use is on PATH, every feature's own run.sh resolves the rest of
# its dependencies (starting with `zz_use perspikapps/vps/common`) on
# demand the same way — see README.md's "Replicating this pattern in
# another repo".

set -eu

ZZ_SCRIPTS_REF="${ZZ_SCRIPTS_REF:-main}"
ZZ_SCRIPTS_SETUP_URL="${ZZ_SCRIPTS_SETUP_URL:-https://raw.githubusercontent.com/tomgrv/scripts/${ZZ_SCRIPTS_REF}/setup.sh}"

curl -fsSL "$ZZ_SCRIPTS_SETUP_URL" | sh -s -- "$ZZ_SCRIPTS_REF"
