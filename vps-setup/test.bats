#!/usr/bin/env bats
# Checks for vps-setup/ - a thin wrapper around zz-setup, not an installable
# step itself (excluded from zz-setup's feature discovery by having no "vps"
# key in its package.json, like vps-common). Feature discovery, menus and
# input handling are tested in tomgrv/scripts' zz-setup; a live run needs a
# real root Ubuntu box - see the root README's "Tests" section.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
DIR="$REPO_ROOT/vps-setup"

setup() {
    STUBS=$(mktemp -d)
    # zz-use/vps-common are no-ops; zz-setup just reports what it received.
    printf '#!/bin/sh\nexit 0\n' >"$STUBS/zz-use"
    printf '#!/bin/bash\ntrue\n' >"$STUBS/vps-common"
    printf '#!/bin/sh\necho "zz-setup $*"; echo "foo=$FOO_FROM_FILE"\nexit 1\n' >"$STUBS/zz-setup"
    chmod +x "$STUBS"/*
}

teardown() {
    rm -rf "$STUBS"
}

@test "run.sh parses as POSIX sh" {
    run dash -n "$DIR/run.sh"
    [ "$status" -eq 0 ]
}

@test "run.sh fetches vps-common and zz-setup with zz-use, and sources vps-common" {
    grep -q 'zz-use --force "perspikapps/vps/vps-common@.*" zz-setup' "$DIR/run.sh"
    grep -q '^\. vps-common$' "$DIR/run.sh"
}

@test "run.sh does not bootstrap zz-use itself (assumes setup.sh already ran)" {
    ! grep -q 'command -v zz-use' "$DIR/run.sh"
    ! grep -q 'curl -fsSL.*setup\.sh.*| sh$' "$DIR/run.sh"
}

@test "run.sh leaves discovery, menus and inputs to zz-setup" {
    ! grep -q 'zz-menu\|zz-prompt\|zz-persist' "$DIR/run.sh"
    [ ! -e "$DIR/steps.sh" ]
}

@test "legacy flags are translated to zz-setup lists" {
    run env PATH="$STUBS:$PATH" VPS_SETUP_ENV_FILE=/nonexistent sh "$DIR/run.sh" -h \
        --skip-vps-rancher --skip-vps-k3s --with-vps-cockpit --only-vps-system --down-vps-marketplace --force-down
    [[ "$output" == *"-F -s vps-rancher,vps-k3s -w vps-cockpit -o vps-system -d vps-marketplace"* ]]
}

@test "a full local checkout is used in place" {
    run env PATH="$STUBS:$PATH" VPS_SETUP_ENV_FILE=/nonexistent sh "$DIR/run.sh" -h
    [[ "$output" == *"zz-setup $REPO_ROOT -h"* ]]
}

@test "the settings file is sourced (shell syntax, quotes and comments allowed)" {
    printf 'FOO_FROM_FILE="a b" # a comment\n' >"$STUBS/env"
    cp "$DIR/run.sh" "$STUBS/copy.sh"
    run env PATH="$STUBS:$PATH" VPS_SETUP_ENV_FILE="$STUBS/env" ZZ_SETUP_REF=feat \
        bash -c 'sed "s#^script_dir=.*#script_dir=/nonexistent#" "$0" > "$1" && sh "$1" -h; echo "foo=$FOO_FROM_FILE"' "$DIR/run.sh" "$STUBS/run2.sh"
    [[ "$output" == *"zz-setup perspikapps/vps@feat -h"* ]]
    [[ "$output" == *"foo=a b"* ]]
}

@test "a fork URL is split into zz-setup's base URL and org/repo" {
    run env PATH="$STUBS:$PATH" VPS_SETUP_ENV_FILE=/nonexistent VPS_SETUP_REPO_URL=https://example.com/me/myvps.git \
        bash -c 'sed "s#^script_dir=.*#script_dir=/nonexistent#" "$0" > "$1" && sh "$1" -h' "$DIR/run.sh" "$STUBS/run2.sh"
    [[ "$output" == *"zz-setup me/myvps@main -h"* ]]
}

@test "package.json bin entry matches the folder name" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.bin['vps-setup'] === 'run.sh' ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "package.json depends on @tomgrv/vps-common" {
    run node -e "const p = require('$DIR/package.json'); process.exit(p.dependencies['@tomgrv/vps-common'] === '*' ? 0 : 1)"
    [ "$status" -eq 0 ]
}
