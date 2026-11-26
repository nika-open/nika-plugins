#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# nika-facts — the names an author needs, read from the binary just now.
#
# A skill written last month names last month's builtins and model routes.
# The authoring and running skills run this when they load, so the names in
# front of the agent are the ones this binary serves. Short on purpose: it
# is injected into context, so it prints a handful of lines, each bounded,
# whatever the binary answers. Prints and exits 0 whatever is missing; a skill
# that loads with the injection disabled reads the same names with the
# commands printed in its own first lines.
#
# Every call to the binary has a time limit (5 s each): a skill must load
# even when the binary hangs, and a call that was stopped is a name that
# was not read, which each line below already says.
# NIKA_KIT_TIMEOUT_SECONDS replaces the limit, in whole seconds (tests).
#
# Usage: nika-facts.sh [project-dir]

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
here="$(cd "$(dirname "$0")" && pwd)"
project="${1:-$PWD}"
limit="${NIKA_KIT_TIMEOUT_SECONDS:-5}"
case "$limit" in '' | *[!0-9]*) limit=5 ;; esac

# limited <command…>: its standard output, or nothing when it takes longer
# than the limit (exit 124). The output goes through a file, so a process
# the command left behind cannot hold the caller.
limited() {
  local out pid rc ticks=0
  out="$(mktemp 2>/dev/null)" || return 125
  "$@" >"$out" 2>/dev/null &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$ticks" -ge $((limit * 20)) ]; then
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      rm -f "$out"
      return 124
    fi
    sleep 0.05
    ticks=$((ticks + 1))
  done
  wait "$pid"
  rc=$?
  cat "$out"
  rm -f "$out"
  return "$rc"
}
if [ -x "$here/../bin/nika-kit" ]; then
  bin="$(bash -p "$here/../bin/nika-kit" --path "$project" 2>/dev/null)"
else
  case "${NIKA_BIN:-}" in
    /*) bin="$NIKA_BIN" ;;
    *) bin="$(nika_on_path 2>/dev/null || true)" ;;
  esac
fi
if [ -z "${bin:-}" ] || ! command -v "$bin" >/dev/null 2>&1; then
  echo "Nika facts: no nika binary was found, so no name was read. Install it (curl -LsSf https://nika.sh/install.sh | sh), then read names from \`nika catalog --tools\`, \`nika catalog\` and \`nika spec --canon\`."
  exit 0
fi

echo "Nika facts, read from the binary just now. Trust these names over memory."
echo "- binary: $bin · $(limited "$bin" --version | head -n 1)"
builtins="$(limited "$bin" spec --canon | awk '
  /^builtins:/ { inside = 1 }
  inside && /^  items:/ { items = 1; next }
  inside && items && /^    - / { printf "%snika:%s", (n++ ? ", " : ""), $2; next }
  inside && items { exit }' | cut -c1-1500)"
echo "- builtins: ${builtins:-not listed by \`nika spec --canon\` here; read \`nika catalog --tools\`}"

if command -v python3 >/dev/null 2>&1; then
  # shellcheck disable=SC2016
  limited "$bin" catalog --json | python3 -I -c 'import json, sys
try:
    rows = [p for p in json.load(sys.stdin).get("providers", []) if p.get("resolves")]
except Exception:
    rows = []
routes = ["%s/%s%s" % (p.get("id"), p.get("cheap_model") or p.get("default_model"), " (local)" if p.get("local") else "") for p in rows]
print("- model names this binary knows, one per provider (its cheaper model; `nika catalog` lists every model). A name here is not a key on this machine: `access_plan` in `nika check <file> --json` says which route is ready: " + ("; ".join(routes)[:1500] if routes else "not listed here; read `nika catalog`"))'
  waiting="$(limited python3 -I "$here/nika-pending.py" "$project" --json | python3 -I -c 'import json, sys
try:
    listed = json.load(sys.stdin)
    print("unknown" if listed.get("error") else len(listed.get("waiting", [])))
except Exception:
    print("unknown")' 2>/dev/null)"
  echo "- runs waiting for an answer in $project: ${waiting:-unknown}"
else
  echo "- model routes and waiting runs: python3 is absent; read \`nika catalog\` and \`nika trace ls\`"
fi
if limited "$bin" catalog --help | grep -q -- '--mcp'; then
  echo "- MCP shelf: $(limited "$bin" catalog --mcp | head -n 20 | tr '\n' ' ' | cut -c1-900)"
else
  echo "- MCP shelf: this binary prints no list of it; take a server's launch command from its own documentation"
fi
exit 0
