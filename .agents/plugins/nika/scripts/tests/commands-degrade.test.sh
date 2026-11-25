#!/usr/bin/env bash
# commands-degrade.test · a command that calls a kit script says what to do
# without it.
#
# The helper scripts are reached through the Claude Code plugin root. A host
# that loads the same command files without that root (Cursor lists them in
# its manifest) would hand its agent a line it cannot run. So every command
# that names the plugin root also carries a « without the kit's scripts »
# sentence that gives the same step with the `nika` binary alone, and the
# Cursor manifest says which commands this concerns.
#
# Usage: commands-degrade.test.sh  (exit 0 = all green)
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FAILS=0
bad() {
  echo "FAIL $1"
  FAILS=$((FAILS + 1))
}

backed=""
for command in "$KIT"/commands/*.md; do
  name="$(basename "$command" .md)"
  body="$(awk 'fences >= 2 { print } /^---$/ { fences++ }' "$command")"
  case "$body" in *CLAUDE_PLUGIN_ROOT*) ;; *) continue ;; esac
  backed="$backed $name"
  if tr '\n' ' ' <"$command" | tr -s ' ' | grep -qi "without the kit's scripts"; then echo "ok   /$name says what to do without the kit's scripts"; else
    bad "/$name calls a kit script and never says what to do without it"
  fi
done
[ -n "$backed" ] || bad "no command names the plugin root: this test reads the wrong folder"

cursor="$KIT/.cursor-plugin/plugin.json"
for name in $backed; do
  grep -qF "/${name}" "$cursor" || bad "the Cursor manifest does not list /${name}"
done
grep -q "helper scripts" "$cursor" || bad "the Cursor manifest does not say that some commands use helper scripts"
grep -q "nika binary alone" "$cursor" || bad "the Cursor manifest does not say those commands work with the binary alone"

if [ "$FAILS" -eq 0 ]; then echo "all green"; else
  echo "$FAILS failure(s)"
  exit 1
fi
