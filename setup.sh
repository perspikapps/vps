#!/bin/sh
# Installs zz_use onto PATH. See README.md.

set -eu

ZZ_SCRIPTS_REF="${ZZ_SCRIPTS_REF:-main}"
ZZ_SCRIPTS_SETUP_URL="${ZZ_SCRIPTS_SETUP_URL:-https://raw.githubusercontent.com/tomgrv/scripts/${ZZ_SCRIPTS_REF}/setup.sh}"

curl -fsSL "$ZZ_SCRIPTS_SETUP_URL" | sh -s -- "$ZZ_SCRIPTS_REF"
