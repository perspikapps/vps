#!/bin/sh
# set/ask/run: the three per-step operations dispatch.sh drives - kept in
# their own file so the root script stays focused on flag parsing, the
# menu, and dependency resolution. POSIX /bin/sh, same as dispatch.sh
# itself: sourced only after the bootstrap clone (see dispatch.sh) has put
# this file on disk, so it's never needed by the curl | sh bootstrap path.
#
# Expects log/warn/die, ALL_NAMES, feature_dir_for_name, feature_desc,
# feature_inputs, and pkg_input_* (all defined earlier in dispatch.sh) to
# already be in scope - this file only adds functions, so sourcing it
# early (before any of those run) is fine.

# --- set: per-feature state (up/skip/down), emulated with eval'd
# variables (POSIX sh has no arrays/maps): STATE_<name> holds it.
#
# Feature short names may contain hyphens (e.g. "github-arc"), which
# aren't valid in a shell variable name - translate to underscores for the
# eval'd STATE_<name> variable itself; state_get/state_set still
# take/return the real hyphenated name everywhere else.

state_var() { printf '%s' "$1" | tr '-' '_'; }
state_get() { eval "printf '%s' \"\${STATE_$(state_var "$1"):-skip}\""; }
state_set() { eval "STATE_$(state_var "$1")=\$2"; }

# --- ask: prompt for any input an enabled ("up") step declares in its own
# package.json ("config.inputs" - see pkg_input_names) that isn't already
# set in the environment, so a plain interactive run doesn't need every
# env var pre-set on the command line. Only runs on an actual terminal:
# curl | sudo sh pipes the script itself into stdin, so there's nothing to
# read prompts from there - env vars (or --skip-*) are the only way to
# supply them in that mode.

ask_missing_inputs() {
  [ -t 0 ] || return 0
  echo
  echo "==== Feature inputs ===="
  for name in $ALL_NAMES; do
    [ "$(state_get "$name")" = "up" ] || continue
    d=$(feature_dir_for_name "$name")
    pkg="${d}/package.json"
    for input in $(feature_inputs "$d"); do
      current=$(eval "printf '%s' \"\${${input}:-}\"")
      [ -n "$current" ] && continue

      desc=$(pkg_input_description "$pkg" "$input")
      required=$(pkg_input_required "$pkg" "$input")
      default=$(pkg_input_default "$pkg" "$input")

      prompt="  ${input}"
      [ -n "$desc" ] && prompt="${prompt} (${desc})"
      if [ -n "$default" ]; then
        prompt="${prompt} [${default}]: "
      elif [ "$required" = "true" ]; then
        prompt="${prompt} (required): "
      else
        prompt="${prompt} [optional, enter to skip]: "
      fi
      printf '%s' "$prompt"
      read -r answer
      [ -z "$answer" ] && answer="$default"

      if [ -n "$answer" ]; then
        eval "${input}=\"\${answer}\""
        eval "export ${input}"
      elif [ "$required" = "true" ]; then
        warn "${input} is required by '${name}' but was left empty; that step will likely fail without it."
      fi
    done
  done
}

# --- run: execute one feature's run.sh with the given action, dying with
# a clear message (and a one-liner to re-run just this step) on failure.

run_step() {
  # $1=name $2=action
  d=$(feature_dir_for_name "$1")
  label="$(feature_desc "$d")"
  log "=== Running ${label} ($(basename "$d")/run.sh $2) ==="
  rc=0
  bash "$d/run.sh" "$2" || rc=$?
  if [ "$rc" -ne 0 ]; then
    die "Step '${label}' ($(basename "$d")/run.sh $2) failed (exit ${rc}) - see the error above. Fix it and re-run just this step with: sudo sh dispatch.sh --only-${1}"
  fi
  ok "=== Done: ${label} (${2}) ==="
}
