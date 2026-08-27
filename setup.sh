#!/bin/sh
# Installs zz_use + the common zz_* bundle, then execs this repo's main
# entrypoint (package.json "main" - dispatch.sh - falling back to a root
# main.sh, or stopping if neither is found next to this script). See
# README.md.

set -eu

ZZ_SCRIPTS_REF="${ZZ_SCRIPTS_REF:-main}"
ZZ_SCRIPTS_SETUP_URL="${ZZ_SCRIPTS_SETUP_URL:-https://raw.githubusercontent.com/tomgrv/scripts/${ZZ_SCRIPTS_REF}/setup.sh}"

curl -fsSL "$ZZ_SCRIPTS_SETUP_URL" | sh -s -- "$ZZ_SCRIPTS_REF"

ZZ_SCRIPTS_SETUP_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || ZZ_SCRIPTS_SETUP_DIR=""

if [ -n "$ZZ_SCRIPTS_SETUP_DIR" ] && [ -f "$ZZ_SCRIPTS_SETUP_DIR/package.json" ]; then
  MAIN=$(sed -n 's/^[[:space:]]*"main"[[:space:]]*:[[:space:]]*"\(.*\)"[,]*[[:space:]]*$/\1/p' "$ZZ_SCRIPTS_SETUP_DIR/package.json" | head -n1)
  if [ -n "$MAIN" ] && [ -f "$ZZ_SCRIPTS_SETUP_DIR/$MAIN" ]; then
    exec sh "$ZZ_SCRIPTS_SETUP_DIR/$MAIN" "$@"
  fi
fi

if [ -n "$ZZ_SCRIPTS_SETUP_DIR" ] && [ -f "$ZZ_SCRIPTS_SETUP_DIR/main.sh" ]; then
  exec sh "$ZZ_SCRIPTS_SETUP_DIR/main.sh" "$@"
fi
