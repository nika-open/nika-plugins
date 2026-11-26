#!/usr/bin/env bash
# python-hook <script> [argument...]: start one of the kit's Python hook
# scripts the way no environment variable can change.
#
# A host that started a Python hook by its shebang (#!/usr/bin/env python3)
# took python3 from the PATH it was given and started it without -I: that
# interpreter read PYTHONHOME, PYTHONPATH and the user's site folder before
# the script's first line, whatever the script did next. The kit's manifests
# start this launcher instead, with /bin/bash -p. It sets the PATH with the
# block every kit script shares, finds python3 there as an absolute path,
# and runs the script with -I from the start: no PYTHON* variable, no site
# folder, no working folder decides what the interpreter loads.
#
# The script is one of the .py files beside this launcher, named alone (no
# folder in the name). Without python3 on the PATH the hook cannot start:
# the launcher says so on stderr and exits 1, the non-blocking error every
# host shows, as the shebang did.

# >>> nika-clean-path: every kit hook and helper opens with this same block,
# before it starts any other program (a test keeps the copies identical).
# Hosts start hooks in the open project, and the PATH can name folders the
# repository holds: a relative entry (".", "bin", "node_modules/.bin", the
# empty one) resolves there, and an absolute one can lead there too. Only
# the absolute entries whose real folder (cd -P) lies outside the project
# are kept, as those real folders. The project is each of
# CLAUDE_PROJECT_DIR, CURSOR_PROJECT_DIR and the working folder, with the
# git work tree around each (the nearest folder above holding .git), but
# never the home or a folder above it. A function of builtins, run once in
# a subshell (bash 3.2 cannot parse a case inside $(...)): nothing runs
# before the PATH is set. The kit's manifests start this script with
# /bin/bash -p (see the README for what that does and does not cover).
nika_clean_path() {
  local here dir top root home kept rest
  here="${PWD:-}"
  set --
  home=/
  case "${HOME:-}" in
    /*) cd -P -- "$HOME" 2>/dev/null && home="$PWD" ;;
  esac
  for dir in "${CLAUDE_PROJECT_DIR:-}" "${CURSOR_PROJECT_DIR:-}" "$here"; do
    case "$dir" in
      /*) cd -P -- "$dir" 2>/dev/null || continue ;;
      *) continue ;;
    esac
    top="$PWD"
    while [ -n "$top" ] && [ ! -e "$top/.git" ]; do
      top="${top%/*}"
    done
    for root in "$PWD" "$top"; do
      case "$root" in
        '' | /) continue ;;
      esac
      case "$home/" in
        "$root"/*) continue ;;
      esac
      set -- "$@" "$root"
    done
  done
  kept=""
  rest="${PATH:-}"
  while [ -n "$rest" ]; do
    dir="${rest%%:*}"
    case "$rest" in
      *:*) rest="${rest#*:}" ;;
      *) rest="" ;;
    esac
    case "$dir" in
      /*) cd -P -- "$dir" 2>/dev/null || continue ;;
      *) continue ;;
    esac
    for root; do
      case "$PWD/" in
        "$root"/*) continue 2 ;;
      esac
    done
    kept="${kept:+$kept:}$PWD"
  done
  printf '%s' "$kept"
}
nika_path="$(nika_clean_path)"
unset -f nika_clean_path
PATH="${nika_path:-/usr/bin:/bin}"
export PATH
unset nika_path
# nika_on_path: the nika this PATH names, as an absolute path, when there is
# one. `type -P` searches the PATH alone: a function or an alias named nika
# never answers.
# shellcheck disable=SC2329 # not every script asks for nika
nika_on_path() {
  local bin
  bin="$(type -P nika)" || return 1
  case "$bin" in
    /*) printf '%s\n' "$bin" ;;
    *) return 1 ;;
  esac
}
# <<< nika-clean-path

set -u

name="${1:-}"
case "$name" in
  '' | */* | .*) name="" ;;
  *.py) ;;
  *) name="" ;;
esac
case "$0" in
  */*) here="${0%/*}" ;;
  *) here=. ;;
esac
here="$(cd -P -- "$here" 2>/dev/null && pwd)" || here=""
if [ -z "$name" ] || [ -z "$here" ] || [ ! -f "$here/$name" ]; then
  printf 'python-hook: the argument names no Python script of the kit (a .py file beside this launcher), so no hook ran.\n' >&2
  exit 1
fi
if ! interp="$(type -P python3)"; then
  interp=""
fi
case "$interp" in
  /*) ;;
  *)
    printf 'python-hook: python3 is not on the PATH (its absolute folders), so the %s hook did not run. Install Python 3 where the editor finds it, then restart the session.\n' "$name" >&2
    exit 1
    ;;
esac
shift
exec "$interp" -I "$here/$name" "$@"
