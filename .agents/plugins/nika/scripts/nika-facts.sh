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
  bin="$("$here/../bin/nika-kit" --path "$project" 2>/dev/null)"
else
  bin="${NIKA_BIN:-$(command -v nika 2>/dev/null)}"
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
  limited "$bin" catalog --json | python3 -c 'import json, sys
try:
    rows = [p for p in json.load(sys.stdin).get("providers", []) if p.get("resolves")]
except Exception:
    rows = []
routes = ["%s/%s%s" % (p.get("id"), p.get("cheap_model") or p.get("default_model"), " (local)" if p.get("local") else "") for p in rows]
print("- model names this binary knows, one per provider (its cheaper model; `nika catalog` lists every model). A name here is not a key on this machine: `access_plan` in `nika check <file> --json` says which route is ready: " + ("; ".join(routes)[:1500] if routes else "not listed here; read `nika catalog`"))'
  waiting="$(limited "$here/nika-pending.py" "$project" --json | python3 -c 'import json, sys
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
