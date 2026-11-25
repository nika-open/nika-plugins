#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# run-progress — a monitor: while a run started in this session is going,
# print one line when a task fails, is recovered or pauses, and one line
# when metered spend passes half, then nine tenths, of the run's ceiling.
# A task that succeeds prints nothing: a quiet monitor is the point.
#
# It reads the trace files only (.nika/traces/*.ndjson), never the binary,
# and takes the ceiling from the trace itself (`budget` on the first
# event): a monitor is not given the plugin's settings. It prints task and
# workflow names, never the text a run recorded. Nothing readable, no
# trace store, a half-written line, a line that is JSON without being an
# event: it stays silent and tries again, and what it already said is
# written down whatever a line holds, so no line is ever said twice.
#
# NIKA_PROGRESS_POLL_SECONDS (default 15) sets the pace;
# NIKA_PROGRESS_ONCE=1 runs a single pass, NIKA_PROGRESS_SINCE=<unix
# seconds> replaces "since this monitor started" and NIKA_PROGRESS_STATE
# names the file that remembers what was said (tests).
set -u
state="${NIKA_PROGRESS_STATE:-}"
if [ -z "$state" ]; then
  state="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/nika-progress-$$")"
  trap 'rm -f "$state"' EXIT
fi
since="${NIKA_PROGRESS_SINCE:-$(($(date +%s) - 60))}"
while :; do
  if [ -d .nika/traces ] && command -v python3 >/dev/null 2>&1; then
    python3 -c 'import glob, json, os, re, sys
state_path, since = sys.argv[1], float(sys.argv[2])
try:
    said = set(json.load(open(state_path)))
except (OSError, ValueError):
    said = set()
plain = lambda v: re.sub(r"[^A-Za-z0-9_.:/-]", "", str(v or "?"))[:60] or "?"
def code(fields):
    found = re.search(r"NIKA-[A-Z0-9_-]+", str(fields.get("code") or fields.get("detail") or ""))
    return found.group(0) if found else "no code recorded"
def scan(path):
    try:
        if os.path.getmtime(path) < since:
            return
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return
    name, ceiling, spent = "?", None, 0.0
    for line in lines:
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if not isinstance(event, dict):
            continue
        rows = event.get("fields")
        fields = {f.get("key"): f.get("value") for f in rows if isinstance(f, dict) and isinstance(f.get("key"), str)} if isinstance(rows, list) else {}
        kind, task = event.get("kind"), plain(fields.get("task"))
        notes = []
        if kind == "workflow_started":
            name = plain(fields.get("workflow"))
            try:
                ceiling = float(json.loads(fields.get("budget") or "{}").get("max_cost_usd"))
            except (ValueError, TypeError, AttributeError):
                ceiling = None
        elif kind == "task_failed":
            notes.append((task + ":failed", "task %s failed (%s)" % (task, code(fields))))
        elif kind == "task_recovered":
            notes.append((task + ":recovered", "task %s failed and was recovered (%s)" % (task, code(fields))))
        elif kind == "workflow_paused":
            notes.append((task + ":paused", "paused at %s, waiting for an answer (/nika:pending)" % task))
        try:
            spent += float(fields.get("cost_usd") or 0)
        except (ValueError, TypeError):
            pass
        if ceiling and ceiling > 0:
            for mark, label in ((0.5, "half"), (0.9, "nine tenths")):
                if spent >= mark * ceiling:
                    notes.append(("spend:" + label, "metered spend passed %s of the $%.2f ceiling ($%.4f so far)" % (label, ceiling, spent)))
        for key, text in notes:
            if path + "|" + key not in said:
                said.add(path + "|" + key)
                print("Nika run %s: %s" % (name, text), flush=True)
try:
    for path in sorted(glob.glob(".nika/traces/*.ndjson")):
        try:
            scan(path)
        except Exception:
            continue
finally:
    try:
        json.dump(sorted(said), open(state_path, "w"))
    except OSError:
        pass' "$state" "$since"
  fi
  [ "${NIKA_PROGRESS_ONCE:-0}" = "1" ] && exit 0
  sleep "${NIKA_PROGRESS_POLL_SECONDS:-15}"
done
