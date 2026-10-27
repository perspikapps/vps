#!/usr/bin/env bats
# Static checks for app-github-arc/run.sh and package.json - the install needs a live cluster.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
DIR="$REPO_ROOT/app-github-arc"

@test "run.sh parses as POSIX sh" {
    run dash -n "$DIR/run.sh"
    [ "$status" -eq 0 ]
}

@test "up, down and summary go through app-helm for the github-arc chart" {
    grep -q 'app-helm up github-arc' "$DIR/run.sh"
    grep -q 'app-helm down github-arc' "$DIR/run.sh"
    grep -q 'app-helm summary github-arc' "$DIR/run.sh"
    [ -f "$REPO_ROOT/charts/github-arc/Chart.yaml" ]
}

@test "it is an opt-in step after the cluster, with its bin named like the folder" {
    run node -e "const p = require('$DIR/package.json'); const k = require('$REPO_ROOT/vps-k3s/package.json'); process.exit(p.bin['app-github-arc'] === 'run.sh' && p.config.default === false && p.config.order > k.config.order && p.engines['zz-setup'] ? 0 : 1)"
    [ "$status" -eq 0 ]
}

@test "visibility is declared exactly when the chart takes an access value" {
    run node -e "const p = require('$DIR/package.json'); process.exit((false) === ('visibility' in p.config) ? 0 : 1)"
    [ "$status" -eq 0 ]
}
