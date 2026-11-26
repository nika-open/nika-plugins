#!/usr/bin/env bash
# guard-timeouts.test.sh: every wiring of the run guard waits longer than
# the guard waits for its judge.
#
# A host that times a hook out lets the action through. guard-run.sh holds
# `nika guard` to a fixed deadline (its `deadline=` line) and refuses past
# it, so each kit manifest that starts the guard must give the hook a
# timeout above that deadline: Claude Code's (hooks/claude-hooks.json, which
# the Codex plugin names too) and Cursor's (hooks/cursor-hooks.json), both
# in seconds. None of them sets a blocking-failure option (Claude Code
# onFailure, Cursor failClosed): the guard's warning outside a Nika project
# is a non-blocking exit 1 on purpose. The project wiring `nika init` writes
# is held to the same rule by the engine's own tests.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$(cd "$HERE/../.." && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL guard-timeouts.test: python3 is absent, so no timeout was compared" >&2
  exit 1
fi

if python3 -I - "$KIT" <<'PY'; then
import json, os, re, sys

kit = sys.argv[1]
fails = []
lines = open(os.path.join(kit, "scripts", "guard-run.sh"), encoding="utf-8").read().splitlines()
deadlines = [int(m.group(1)) for line in lines for m in [re.fullmatch(r"deadline=(\d+)", line)] if m]
if len(deadlines) != 1:
    print("FAIL  guard-run.sh holds %d deadline= lines, not one" % len(deadlines))
    sys.exit(1)
deadline = deadlines[0]

def guards(manifest, event, nested):
    data = json.load(open(os.path.join(kit, "hooks", manifest), encoding="utf-8"))
    entries = data["hooks"].get(event, [])
    hooks = [hook for entry in entries for hook in entry["hooks"]] if nested else entries
    return data, [hook for hook in hooks if hook.get("command", "").endswith("guard-run.sh")]

def blocking(node):
    if isinstance(node, dict):
        return any(key in ("failClosed", "onFailure") or blocking(value) for key, value in node.items())
    if isinstance(node, list):
        return any(blocking(value) for value in node)
    return False

for manifest, event, nested in [("claude-hooks.json", "PreToolUse", True), ("cursor-hooks.json", "beforeShellExecution", False)]:
    data, found = guards(manifest, event, nested)
    if len(found) != 1:
        fails.append("%s: %d guard hooks under %s, not one" % (manifest, len(found), event))
        continue
    timeout = found[0].get("timeout")
    if not isinstance(timeout, int) or isinstance(timeout, bool) or timeout <= deadline:
        fails.append("%s: the guard's timeout is %r, not a whole number of seconds above the %d s deadline" % (manifest, timeout, deadline))
    else:
        print("ok    %s · the guard's timeout, %d s, is above its %d s deadline" % (manifest, timeout, deadline))
    if blocking(data):
        fails.append("%s: a blocking-failure option is set" % manifest)
    else:
        print("ok    %s · no blocking-failure option" % manifest)
for fail in fails:
    print("FAIL  " + fail)
sys.exit(1 if fails else 0)
PY
  printf 'OK  each guard wiring waits longer than its deadline\n'
else
  printf 'FAIL  guard-timeouts.test\n' >&2
  exit 1
fi
