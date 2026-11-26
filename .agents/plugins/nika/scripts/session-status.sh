#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# session-status — SessionStart: the two things a person must hear FIRST.
#
#   1. The Nika program is missing. The plugin's guard then refuses every
#      shell command inside a Nika project (it cannot judge without its
#      judge) and lets them through, unjudged, elsewhere. Say so at once,
#      with the install line, instead of letting the first `ls` fail with
#      no warning.
#   2. A run in THIS workspace is waiting for an answer (a scheduled run
#      parked at night, a run left before a meeting).
#
# It also drops a per-session marker so stop-gate.sh and precompact-notes.py
# know which workflow files changed during the session. The marker is
# written once, at the first start of a session: its first line and its
# modification time both say when that was. A later start of the same
# session (a resume, a compaction) finds it and leaves it untouched, so a
# workflow written before the compaction still counts as changed. Silence
# when there is nothing to say.

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
input="$(cat 2>/dev/null || true)"

emit() {
  # $1 = plain text for the agent. JSON-escape with python3 when present,
  # with sed otherwise (the missing-binary note is fixed ASCII text).
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -I -c 'import json,sys
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": sys.stdin.read()}}))'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')"
  fi
}

session="$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/' | tr -cd 'A-Za-z0-9_-')"
dir="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}"
if [ -n "$session" ] && [ ! -e "$dir/nika-session-$session" ]; then
  mkdir -p "$dir" 2>/dev/null && printf 'started %s\n' "$(date +%s)" >"$dir/nika-session-$session" 2>/dev/null
fi

if ! nika_on_path >/dev/null 2>&1; then
  emit "The Nika plugin is installed but the nika program is not on PATH. Until it is, the plugin refuses every shell command inside a Nika project (a folder with a nika.yaml or a .nika/ folder, or any folder below one); elsewhere shell commands run, but no nika run is checked before it starts. Tell the user this now, before anything else, in one or two sentences. To fix: brew install nika-open/tap/nika, or curl -LsSf https://nika.sh/install.sh | sh, then restart the session. To work without Nika: disable the plugin. Inside a Nika project, do not try shell commands until one of the two is done."
  exit 0
fi

cwd="$(printf '%s' "$input" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 | sed 's/^"cwd"[[:space:]]*:[[:space:]]*"//; s/"$//')"
# A path with JSON escapes does not survive the line above: decode properly.
if [ ! -d "$cwd" ] && command -v python3 >/dev/null 2>&1; then
  cwd="$(printf '%s' "$input" | python3 -I -c 'import json,sys
try:
    print(json.load(sys.stdin).get("cwd", ""))
except Exception:
    print("")' 2>/dev/null)"
fi
# The payload cwd is the only evidence of a project; the hook cwd is not.
[ -n "$cwd" ] && [ -d "$cwd/.nika/traces" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

here="$(cd "$(dirname "$0")" && pwd)"
out="$(python3 -I "$here/nika-pending.py" "$cwd" 2>/dev/null)"
rc=$?
[ "$rc" -eq 4 ] && [ -n "$out" ] || exit 0
emit "A Nika run in this workspace is waiting for the user. Tell them first, in one or two sentences, and offer /nika:pending. Never answer for them.
$out"
exit 0
