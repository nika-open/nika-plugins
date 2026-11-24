#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# stop-gate — Stop: the agent does not hand back a workflow that fails
# `nika check` without saying so.
#
# Edit hooks and the language server see files changed through the edit
# tools. A workflow written through the shell (a heredoc, a script, a
# generator) passes under both. This gate looks at the end of the turn
# instead: every .nika file changed since the session started is checked,
# and a failing one sends the agent back ONCE with the reason in plain
# words — to fix it, or to tell the user it is left that way on purpose.
#
# Laws: never blocks twice in a row (stop_hook_active) · reports each
# version of a file once (path + mtime remembered in the session marker) ·
# at most 5 files a turn · silent and free (one `find`) when no workflow
# changed · exit 0 when nika, python3 or the session marker is missing.
set -u
input="$(cat 2>/dev/null || true)"
case "$input" in *'"stop_hook_active":true'* | *'"stop_hook_active": true'*) exit 0 ;; esac
command -v nika >/dev/null 2>&1 || exit 0

session="$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/' | tr -cd 'A-Za-z0-9_-')"
[ -n "$session" ] || exit 0
marker="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}/nika-session-$session"
[ -f "$marker" ] || exit 0

cwd="$(printf '%s' "$input" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 | sed 's/^"cwd"[[:space:]]*:[[:space:]]*"//; s/"$//')"
# A path with JSON escapes does not survive the line above: decode properly.
if [ ! -d "$cwd" ] && command -v python3 >/dev/null 2>&1; then
  cwd="$(printf '%s' "$input" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("cwd", ""))
except Exception:
    print("")' 2>/dev/null)"
fi
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0

changed="$(cd "$cwd" && find . -maxdepth 4 \( -name node_modules -o -name .git -o -name target -o -name dist -o -name .nika \) -prune -o -type f -name '*.nika' -newer "$marker" -print 2>/dev/null | head -n 5)"
[ -n "$changed" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

here="$(cd "$(dirname "$0")" && pwd)"
report=""
while IFS= read -r file; do
  [ -n "$file" ] || continue
  stamp="$file $(cd "$cwd" && (stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null))"
  grep -Fqx "$stamp" "$marker" 2>/dev/null && continue
  verdict="$(cd "$cwd" && "$here/nika-verdict.py" "$file" 2>/dev/null)"
  rc=$?
  [ "$rc" -eq 0 ] && continue
  printf '%s\n' "$stamp" >>"$marker"
  # The verdict line and up to three plain reasons under it.
  why="$(printf '%s\n' "$verdict" | sed -n '/^Verdict:/,$p' | head -n 4)"
  report="$report
- ${file#./}: ${why:-Verdict: nika check did not pass (run nika check on it for the reason).}"
done <<EOF_FILES
$changed
EOF_FILES

[ -n "$report" ] || exit 0
printf 'Before you finish: a workflow changed in this session does not pass nika check.%s\nFix it now, or, if you are leaving it this way on purpose, tell the user so in plain words (what is wrong, and that it must not be run yet). You will not be stopped a second time.\n' "$report" >&2
exit 2
