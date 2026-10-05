#!/bin/sh
# set/ask/run: the three per-step operations vps-setup/run.sh drives -
# kept in their own file so that script stays focused on flag parsing,
# the menu, and dependency resolution. POSIX /bin/sh, same as run.sh
# itself.
#
# Expects zz_log/ok (from vps-common), ALL_NAMES, feature_dir_for_name,
# feature_desc, feature_inputs, and pkg_input_* (all defined earlier in
# run.sh) to already be in scope - this file only adds functions, so
# sourcing it early (before any of those run) is fine.

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

# --- ask: let the user fill in any input an enabled ("up") step declares in
# its own package.json ("vps.inputs" - see pkg_input_names) that isn't
# already set in the environment, so a plain interactive run doesn't need
# every env var pre-set on the command line. Every such input is listed in a
# zz_menu (value never shown, only whether it is set); picking one asks for
# its value with zz_prompt, <enter> proceeds, q aborts before anything has
# been installed. Each answer is persisted to VPS_SETUP_ENV_FILE via
# zz_persist, so a later re-run shows that input as already "set" (loaded
# from the file below) instead of asking again - the file itself is never
# echoed back into the menu, so a persisted secret still never prints. Only
# runs on an actual terminal: curl | sudo sh pipes the script itself into
# stdin, so there's nothing to read prompts from there - env vars (or
# --skip-*) are the only way to supply them in that mode.

# input_status <input> <package.json> -> "set", "required" or "optional"
input_status() {
  if [ -n "$(eval "printf '%s' \"\${${1}:-}\"")" ]; then
    echo set
  elif [ "$(pkg_input_required "$2" "$1")" = "true" ]; then
    echo required
  else
    echo optional
  fi
}

ask_missing_inputs() {
  [ -t 0 ] || return 0

  envfile="${VPS_SETUP_ENV_FILE:-/etc/vps-setup.env}"
  if [ -f "$envfile" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$envfile"
    set +a
  fi

  while :; do
    set --
    seen=" "
    unset_count=0
    for name in $ALL_NAMES; do
      [ "$(state_get "$name")" = "up" ] || continue
      d=$(feature_dir_for_name "$name")
      pkg="${d}/package.json"
      for input in $(feature_inputs "$d"); do
        case "$seen" in *" $input "*) continue ;; esac
        seen="$seen$input "
        eval "_owner_${input}=\$name"

        status=$(input_status "$input" "$pkg")
        [ "$status" = "set" ] || unset_count=$((unset_count + 1))
        desc=$(pkg_input_description "$pkg" "$input")
        set -- "$@" "$input=$(printf '%-24s' "$input") [$(printf '%-8s' "$status")] ${name}${desc:+ - $desc}"
      done
    done

    # Nothing left to fill in (or nothing declared at all): no menu.
    [ "$unset_count" -gt 0 ] || return 0

    rc=0
    choice=$(zz_menu -t "Feature inputs" \
      -f "  Number sets that input; <enter> proceeds with what's set, q quits." \
      "$@") || rc=$?
    case "$rc" in
    0) ;;
    1)
      echo "Aborted, nothing changed."
      exit 0
      ;;
    *) break ;;
    esac

    eval "owner=\$_owner_${choice}"
    pkg="$(feature_dir_for_name "$owner")/package.json"
    desc=$(pkg_input_description "$pkg" "$choice")
    default=$(pkg_input_default "$pkg" "$choice")
    current=$(eval "printf '%s' \"\${${choice}:-}\"")

    # A value already set is never echoed back as a default (it may be a
    # secret); an empty answer then simply keeps it.
    if [ -n "$current" ]; then
      answer=$(zz_prompt "${choice}${desc:+ ($desc)} - enter to keep the current value:")
    else
      answer=$(zz_prompt "${choice}${desc:+ ($desc)}:" "$default")
    fi

    if [ -n "$answer" ]; then
      eval "${choice}=\"\${answer}\""
      eval "export ${choice}"
      # Single-quote the value (escaping any embedded "'") before handing it
      # to zz_persist: it writes KEY=<value> verbatim, and an unquoted value
      # containing spaces or shell metacharacters (e.g. an SSH public key,
      # "ssh-ed25519 AAAA... user@host") would corrupt the sourced env file
      # on the next run.
      answer_quoted=$(printf '%s' "$answer" | sed "s/'/'\\\\''/g")
      zz_persist -f "$envfile" "$choice" "'$answer_quoted'"
    fi
  done

  # Whatever is still empty and required is only a warning, as before.
  for name in $ALL_NAMES; do
    [ "$(state_get "$name")" = "up" ] || continue
    d=$(feature_dir_for_name "$name")
    for input in $(feature_inputs "$d"); do
      [ "$(input_status "$input" "${d}/package.json")" = "required" ] || continue
      zz_log w "[vps-setup] ${input} is required by '${name}' but was left empty; that step will likely fail without it."
    done
  done
}

# --- run: execute one feature's run.sh with the given action, dying with
# a clear message (and a one-liner to re-run just this step) on failure.

run_step() {
  # $1=name $2=action
  d=$(feature_dir_for_name "$1")
  label="$(feature_desc "$d")"
  zz_log i "[vps-setup] === Running ${label} ($(basename "$d")/run.sh $2) ==="
  rc=0
  bash "$d/run.sh" "$2" || rc=$?
  if [ "$rc" -ne 0 ]; then
    zz_log e "[vps-setup] Step '${label}' ($(basename "$d")/run.sh $2) failed (exit ${rc}) - see the error above. Fix it and re-run just this step with: sudo vps-setup --only-${1}"
    exit 1
  fi
  ok "=== Done: ${label} (${2}) ==="
}
