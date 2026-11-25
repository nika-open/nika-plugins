#!/usr/bin/env bash
# workflow-scripts.test · the workflow scripts keep the shape their runner needs.
#
# A workflow script is run by the host, not by this repository, so nothing
# here executes one. What can be proven without a session: `meta` is a plain
# literal on the first line and names the file, every phase started in the
# body is declared in `meta` (titles are matched exactly), the body reads no
# clock, no randomness and no file (a resumed run would diverge), and the
# file parses once wrapped the way the runner wraps it.
#
# Usage: workflow-scripts.test.sh  (exit 0 = all green)
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
bad() {
  echo "FAIL $1"
  FAILS=$((FAILS + 1))
}

count=0
for script in "$KIT"/workflows/*.js; do
  [ -f "$script" ] || continue
  count=$((count + 1))
  name="$(basename "$script" .js)"
  if [ "$(head -n 1 "$script")" = "export const meta = {" ]; then echo "ok   $name starts with its meta literal"; else
    bad "$name does not start with « export const meta = { »"
  fi
  grep -qF "name: '$name'," "$script" || bad "$name: meta.name is not the file name"
  for banned in 'import(' 'require(' 'Date.now' 'new Date(' 'Math.random' 'process.' 'readFile' 'writeFile'; do
    if grep -qF -- "$banned" "$script"; then bad "$name uses $banned, which a workflow script cannot"; fi
  done
  declared="$(grep -o "{ title: '[^']*'" "$script" | sed "s/.*'\(.*\)'/\1/" | sort -u)"
  started="$({
    grep -o "^phase('[^']*')" "$script" | sed "s/.*('\(.*\)')/\1/"
    grep -o "phase: '[^']*'" "$script" | sed "s/.*'\(.*\)'/\1/"
  } | sort -u)"
  if [ -n "$declared" ] && [ "$declared" = "$started" ]; then echo "ok   $name declares the phases it starts"; else
    bad "$name: phases declared in meta and phases started differ"
  fi
  if command -v node >/dev/null 2>&1; then
    {
      echo 'async function workflowBody(args, agent, parallel, pipeline, phase, log, budget, workflow) {'
      sed '1s/^export const meta/const meta/' "$script"
      echo '}'
    } >"$TMP/$name.mjs"
    if node --check "$TMP/$name.mjs" 2>"$TMP/err"; then echo "ok   $name parses"; else
      bad "$name does not parse: $(head -n 3 "$TMP/err" | tr '\n' ' ')"
    fi
  else
    echo "skip $name syntax: no node on this machine"
  fi
done
[ "$count" -ge 3 ] || bad "expected the three workflow scripts, found $count"

# A script that starts one agent per file is capped, and a listing that gave
# no result is a stated end, not a crash on a missing value.
for name in port-to-nika nika-audit; do
  script="$KIT/workflows/$name.js"
  if grep -qF 'pipeline(batch,' "$script" && grep -qF '.slice(0, MAX_FILES)' "$script" && ! grep -qF 'pipeline(found.files' "$script"; then
    echo "ok   $name runs its agents over a capped list"
  else bad "$name starts one agent per file with no cap"; fi
  if grep -qF "found && Array.isArray(found.files)" "$script" && grep -qF "The file listing gave no result." "$script"; then
    echo "ok   $name ends plainly when the listing gave no result"
  else bad "$name does not guard a missing file listing"; fi
done
if grep -qF 'runs nothing for real' "$KIT/workflows/nika-forge.js"; then
  bad "nika-forge says it runs nothing for real while its reviewer rehearses"
else echo "ok   nika-forge says what its one rehearsal does"; fi

if [ "$FAILS" -eq 0 ]; then echo "all green"; else
  echo "$FAILS failure(s)"
  exit 1
fi
