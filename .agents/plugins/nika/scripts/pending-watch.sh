#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# pending-watch — a monitor: while a session is open, print ONE line each
# time a Nika run in the working directory starts waiting for an answer.
# Nothing waits → nothing is printed. It never answers and never resumes.
#
# NIKA_PENDING_POLL_SECONDS (default 20) sets the pace;
# NIKA_PENDING_WATCH_ONCE=1 runs a single pass (tests).
set -u
here="$(cd "$(dirname "$0")" && pwd)"
seen="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/nika-watch-$$")"
trap 'rm -f "$seen"' EXIT
while :; do
  if [ -d .nika/traces ] && command -v nika >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    "$here/nika-pending.py" --json 2>/dev/null | python3 -c 'import json,sys
seen_path = sys.argv[1]
try:
    seen = set(open(seen_path).read().split())
except OSError:
    seen = set()
try:
    waiting = json.load(sys.stdin).get("waiting", [])
except Exception:
    waiting = []
for item in waiting:
    trace = item.get("trace") or ""
    if trace and trace not in seen:
        seen.add(trace)
        question = " ".join((item.get("question") or "").split())[:160]
        print("Nika: %s is waiting for an answer at %s: %s (use /nika:pending)" % (item.get("workflow"), item.get("task"), question), flush=True)
open(seen_path, "w").write("\n".join(sorted(seen)))' "$seen"
  fi
  [ "${NIKA_PENDING_WATCH_ONCE:-0}" = "1" ] && exit 0
  sleep "${NIKA_PENDING_POLL_SECONDS:-20}"
done
