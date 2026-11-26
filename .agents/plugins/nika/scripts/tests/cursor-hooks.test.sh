#!/usr/bin/env bash
# cursor-hooks.test.sh: the plugin's Cursor hooks file holds to the hooks
# format Cursor documents (https://cursor.com/docs/hooks, read 2026-11-26).
#
#   - `version` is required: the file declares version 1.
#   - A hook that crashes, times out or exits with anything but 2 lets the
#     action through unless it sets `failClosed: true`. No hook of the kit
#     sets it: as on Claude Code and Codex, a hook that cannot start (no
#     /bin/bash) must let the command through rather than refuse every
#     shell command in every folder, and the run guard refuses by its own
#     exit 2.
#   - Plugin hooks run from the plugin's install folder, which
#     CURSOR_PLUGIN_ROOT names, except `stop` and `subagentStop`, which run
#     from the workspace root: there a relative command would name a file of
#     the open project, so a hook of those two events names its script by
#     the one documented anchor, "${CURSOR_PLUGIN_ROOT}"/. Every other
#     command names a script of the kit, relative to the plugin's folder or
#     by that same anchor. The script's path holds no `..` step, and no
#     word follows it: no hook of the kit takes arguments.
#
# The checker runs on the kit's file, then on broken copies of it, each of
# which it must refuse, and on one stop hook anchored at the plugin root,
# which it must accept: a checker that passes everything fails here.
# The .cursor/hooks.json `nika init` writes is held to the same version and
# to no failClosed by the engine's own tests (briefs.rs).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$(cd "$HERE/../.." && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL cursor-hooks.test: python3 is absent, so nothing was checked" >&2
  exit 1
fi

python3 -I - "$KIT" <<'PY'
import copy, json, os, sys

kit = sys.argv[1]
manifest = os.path.join(kit, "hooks", "cursor-hooks.json")
data = json.load(open(manifest, encoding="utf-8"))
ANCHOR = '"${CURSOR_PLUGIN_ROOT}"/'
WORKSPACE_EVENTS = ("stop", "subagentStop")


def problems(data):
    found = []
    version = data.get("version")
    if version != 1 or isinstance(version, bool):
        found.append("version is %r, not 1" % (version,))
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        return found + ["no hooks object"]
    guards = 0
    for event, entries in hooks.items():
        for entry in entries:
            command = entry.get("command", "")
            rest = command[len("/bin/bash -p "):] if command.startswith("/bin/bash -p ") else command
            words = rest.split()
            script = words[0] if words else ""
            if script.startswith(ANCHOR):
                named = script[len(ANCHOR):]
            elif event in WORKSPACE_EVENTS:
                found.append("%s: %s is not anchored at %s, and Cursor runs %s plugin hooks from the workspace root" % (event, script, ANCHOR, event))
                named = None
            elif script.startswith(("/", "$", '"', "~")):
                found.append("%s: %s names its script by another anchor than %s" % (event, script, ANCHOR))
                named = None
            else:
                named = script
            if named is not None and ".." in named.split("/"):
                found.append("%s: %s steps through .., not a path inside the plugin's folder" % (event, script))
            elif named is not None and not os.path.isfile(os.path.join(kit, named)):
                found.append("%s: %s names no script of the kit from the plugin's folder" % (event, script))
            if len(words) > 1:
                found.append("%s: %s is followed by %r, and no hook of the kit takes arguments" % (event, script, " ".join(words[1:])))
            if command.endswith("/guard-run.sh"):
                guards += 1
            if "failClosed" in entry:
                found.append("%s: %s sets failClosed %r, and a hook that cannot start must let the command through" % (event, script, entry["failClosed"]))
    if guards != 1:
        found.append("%d guard hooks, not one" % guards)
    return found


fails = 0
kit_problems = problems(data)
if kit_problems:
    fails += 1
    print("FAIL  the kit's cursor-hooks.json: " + "; ".join(kit_problems))
else:
    print("ok    the kit's cursor-hooks.json: version 1, no failClosed, every command reaches its script")


def broken(label, change, want):
    global fails
    bad = copy.deepcopy(data)
    change(bad)
    got = problems(bad)
    if any(want in line for line in got):
        print("ok    refused: %s" % label)
    else:
        fails += 1
        print("FAIL  not refused: %s (found %r)" % (label, got))


def guard_of(bad):
    return next(e for e in bad["hooks"]["beforeShellExecution"] if e["command"].endswith("/guard-run.sh"))


def stop_hook(script):
    return lambda bad, event: bad["hooks"].setdefault(event, []).append({"command": "/bin/bash -p " + script})


broken("no version", lambda bad: bad.pop("version", None), "version is None")
broken("version 2", lambda bad: bad.update(version=2), "version is 2")
broken("a guard with failClosed true", lambda bad: guard_of(bad).update(failClosed=True), "sets failClosed True")
broken("a guard with failClosed false", lambda bad: guard_of(bad).update(failClosed=False), "sets failClosed False")
broken("a comfort hook with failClosed", lambda bad: bad["hooks"]["afterFileEdit"][0].update(failClosed=True), "sets failClosed True")
for event in WORKSPACE_EVENTS:
    for script in ("./scripts/stop-gate.sh", '"$PWD"/scripts/stop-gate.sh', '"${CURSOR_PROJECT_DIR}"/scripts/stop-gate.sh', "${CURSOR_PLUGIN_ROOT}/scripts/stop-gate.sh"):
        broken("a %s hook at %s" % (event, script),
               lambda bad, event=event, script=script: stop_hook(script)(bad, event),
               "runs %s plugin hooks from the workspace root" % event)
broken("a relative command naming no kit script",
       lambda bad: bad["hooks"]["sessionStart"].append({"command": "/bin/bash -p ./scripts/missing.sh"}),
       "names no script of the kit")
broken("an anchored command naming no kit script",
       lambda bad: bad["hooks"]["sessionStart"].append({"command": '/bin/bash -p "${CURSOR_PLUGIN_ROOT}"/scripts/missing.sh'}),
       "names no script of the kit")
for event, script in (("sessionStart", "./scripts/../scripts/session-context.sh"),
                      ("stop", '"${CURSOR_PLUGIN_ROOT}"/scripts/../scripts/stop-gate.sh'),
                      ("stop", '"${CURSOR_PLUGIN_ROOT}"/../nika/scripts/stop-gate.sh')):
    broken("a %s hook at %s" % (event, script),
           lambda bad, event=event, script=script: stop_hook(script)(bad, event),
           "steps through ..")
for event, script in (("sessionStart", "./scripts/session-context.sh --verbose"),
                      ("stop", '"${CURSOR_PLUGIN_ROOT}"/scripts/stop-gate.sh "$PWD"/x.sh')):
    broken("a %s hook running %s" % (event, script),
           lambda bad, event=event, script=script: stop_hook(script)(bad, event),
           "no hook of the kit takes arguments")
broken("a command anchored elsewhere",
       lambda bad: bad["hooks"]["sessionStart"].append({"command": '/bin/bash -p "${CURSOR_PROJECT_DIR}"/scripts/session-context.sh'}),
       "names its script by another anchor")
anchored = copy.deepcopy(data)
anchored["hooks"]["stop"] = [{"command": '/bin/bash -p "${CURSOR_PLUGIN_ROOT}"/scripts/stop-gate.sh'}]
anchored["hooks"]["subagentStop"] = [{"command": '/bin/bash -p "${CURSOR_PLUGIN_ROOT}"/scripts/stop-gate.sh'}]
if problems(anchored):
    fails += 1
    print("FAIL  stop hooks anchored at the plugin root were refused: %r" % problems(anchored))
else:
    print("ok    stop hooks anchored at the plugin root are accepted")
sys.exit(1 if fails else 0)
PY
rc=$?
if [ "$rc" -ne 0 ]; then
  printf 'FAIL  cursor-hooks.test\n' >&2
  exit 1
fi
printf 'OK  the Cursor hooks file declares its version, sets no failClosed and anchors its commands\n'
