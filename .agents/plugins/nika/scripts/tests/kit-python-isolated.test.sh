#!/usr/bin/env bash
# kit-python-isolated.test.sh: no file in the open project changes what the
# kit's Python imports.
#
# Python started with -c, -m or a program on stdin puts the working folder
# first on its import path, and hosts start hooks in the project, so a
# repository holding a json.py would run it. Isolated mode (-I) leaves that
# folder out. A script run by its path puts its own folder first instead,
# which is the kit's, but started through its shebang it runs without -I,
# so PYTHONPATH still comes before the standard library: every kit Python
# script starts itself again in isolated mode before its first import. The
# kit's manifests start the Python hooks through python-hook.sh, which runs
# them with -I from the start.
#
# Three proofs:
#   1. The law: every python3 call in the kit that would read the working
#      folder (-c, -m, a program on stdin) carries -I. The scanner is played
#      on samples first, so a scanner that sees nothing fails.
#   2. The entry points: every hook, monitor and helper that starts Python
#      runs from a folder holding a json.py and a glob.py that write a
#      marker, then hand over the real module. The kit must leave no marker.
#      A copy of the kit with -I removed runs the same way and must leave
#      one, which shows that each run reached a Python call.
#   3. The host's environment: every command the hook and monitor manifests
#      name runs as the host runs it, with PYTHONPATH naming a folder that
#      holds the same json.py and glob.py, then again with PYTHONHOME set
#      too (to the interpreter's own prefix, so it still starts). The kit
#      must leave no marker; the copy without -I (in its calls and in the
#      launcher) and without the restart must leave one wherever the run
#      reaches Python.
#
# Stub binaries stand in for nika; no model, no network, no workflow run.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$(cd "$HERE/../.." && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL kit-python-isolated.test: python3 is absent, so nothing was asserted" >&2
  exit 1
fi
fails=0
check() {
  if [ "$2" = yes ]; then
    printf 'ok    %s\n' "$1"
  else
    printf 'FAIL  %s\n      %s\n' "$1" "$3" >&2
    fails=$((fails + 1))
  fi
}

# 1. The law.
if python3 -I - "$KIT" "$HERE/$(basename "${BASH_SOURCE[0]}")" <<'PY'; then
import os, re, sys

CALL = re.compile(r"(?:^|(?<=[\s|;&(`\"'$]))(?:[\w./-]*/)?python3?(?:\.\d+)?(?=\s|$|[;|&)\"'])")
SHELL_STOP = re.compile(r"^([|;&)<>].*|\d>.*|[\"'])$")

def reads_cwd(rest):
    """True when the call reads the working folder and is not isolated."""
    flags, script, stdin = [], False, False
    for tok in rest.split():
        if tok == "-":
            stdin = True
            break
        if tok.startswith("-") and not tok.startswith("--"):
            flags.append(tok)
            if tok[-1] in "cm":
                break
            continue
        if SHELL_STOP.match(tok):
            break
        script = True
        break
    isolated = any("I" in f[1:] for f in flags)
    program = stdin or any(f[-1] in "cm" for f in flags) or not script
    return program and not isolated

def calls(line):
    stripped = line.strip()
    if stripped.startswith("#"):
        return []
    found = []
    for m in CALL.finditer(line):
        before = line[: m.start()]
        if re.search(r"(?:command\s+-v|type\s+-P)\s+$", before):
            continue
        found.append(line[m.end():])
    found += [line[m.end():] for m in re.finditer(r"sys\.executable\s*,\s*(?=[\"']-[cm])", line)]
    return found

def flagged(line):
    return [rest for rest in calls(line) if reads_cwd(rest) or rest.lstrip().startswith(("\"-c", "'-c", "\"-m", "'-m"))]

samples = {
    "printf x | python3 -c 'import json'": True,
    "python3 - \"$KIT\" <<'PY'": True,
    "out=\"$(printf x | python3)\"": True,
    "python3 -m json.tool": True,
    "/usr/bin/python3 -u -c 'x'": True,
    "subprocess.run([sys.executable, \"-c\", code])": True,
    "printf x | python3 -I -c 'import json'": False,
    "python3 -I - \"$KIT\" <<'PY'": False,
    "python3 \"$HERE/nika-card.py\" flow.nika": False,
    "if command -v python3 >/dev/null 2>&1; then": False,
    "if ! interp=\"$(type -P python3)\"; then": False,
    "echo \"python3 is absent, so nothing was asserted\"": False,
    "# whose work happens inside `exec python3 helper.py`": False,
    "#!/usr/bin/env python3": False,
}
wrong = [s for s, want in samples.items() if bool(flagged(s)) != want]
if wrong:
    print("the scanner misreads its samples:", *wrong, sep="\n  ")
    sys.exit(1)

kit, own = sys.argv[1], os.path.realpath(sys.argv[2])
bad, isolated = [], 0
for base, dirs, files in os.walk(kit):
    for name in sorted(files):
        if name.endswith(".md"):
            continue
        path = os.path.join(base, name)
        if os.path.realpath(path) == own:
            continue  # its sample table, played above
        try:
            lines = open(path, encoding="utf-8").read().splitlines()
        except (OSError, UnicodeDecodeError):
            continue
        for n, line in enumerate(lines, 1):
            for rest in calls(line):
                if flagged(line):
                    bad.append("%s:%d: %s" % (os.path.relpath(path, kit), n, line.strip()[:120]))
                    break
                if re.match(r"\s+-I\b", rest):
                    isolated += 1
if bad:
    print("python3 reads the working folder here, without -I:", *bad, sep="\n  ")
    sys.exit(1)
if isolated < 10:
    print("only %d isolated python3 calls found: the scanner reads less than the kit holds" % isolated)
    sys.exit(1)
print("%d isolated python3 calls, none reads the working folder" % isolated)
PY
  check "every python3 call that would read the working folder runs isolated" yes ""
else
  check "every python3 call that would read the working folder runs isolated" no "see above"
fi

# 2. The entry points.
root="$(mktemp -d)"
root="$(cd "$root" && pwd -P)"
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/kit" "$root/open" "$root/stub" "$root/home" "$root/tmp" "$root/data" \
  "$root/project/.nika/traces"
cp -R "$KIT/bin" "$KIT/scripts" "$root/kit/"
cp -R "$KIT/bin" "$KIT/scripts" "$root/open/"
# The control copy: the same kit with isolation taken out.
python3 -I - "$root/open" <<'PY'
import os, sys
for base, dirs, files in os.walk(sys.argv[1]):
    for name in files:
        path = os.path.join(base, name)
        try:
            text = open(path, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        launcher = 'exec "$interp" -I '
        if "python3 -I " in text or "if not sys.flags.isolated:" in text or launcher in text:
            text = text.replace("python3 -I ", "python3 ")
            text = text.replace("if not sys.flags.isolated:", "if False:  # control")
            text = text.replace(launcher, 'exec "$interp" ')
            open(path, "w", encoding="utf-8").write(text)
PY

marker="$root/marker"
for module in json glob; do
  cat >"$root/project/$module.py" <<EOF
import os as _os, sys as _sys
with open("$marker", "a") as _f:
    _f.write("$module.py from the project ran\n")
_here = _os.path.dirname(_os.path.abspath(__file__))
_sys.path[:] = [p for p in _sys.path if _os.path.abspath(p or ".") != _here]
del _sys.modules[__name__]
import $module as _real
_sys.modules[__name__] = _real
EOF
done
printf 'nika: flow\ntasks: {}\n' >"$root/project/flow.nika"
printf 'nika: project\n' >"$root/project/nika.yaml"
: >"$root/data/nika-session-s3"
cat >"$root/stub/nika" <<'EOF'
#!/bin/sh
case "$1" in
  --version) echo "nika 0.0.0 (stub)" ;;
  catalog) echo '{"providers":[{"id":"anthropic","cheap_model":"stub-model","resolves":true}]}' ;;
  arm) echo '{"schedules":[]}' ;;
  trace) echo '[]' ;;
esac
exit 0
EOF
chmod +x "$root/stub/nika"
p="$root/project"

# entry <label> <reaches python -c: yes|no> <payload> <script> [VAR=value...]
entry() {
  local label="$1" reaches="$2" payload="$3" script="$4" tree saw
  shift 4
  for tree in kit open; do
    [ "$tree" = open ] && [ "$reaches" = no ] && continue
    rm -f "$marker"
    (cd "$p" && printf '%s' "$payload" | env -i PATH="$root/stub:/usr/bin:/bin" HOME="$root/home" \
      TMPDIR="$root/tmp" CLAUDE_PLUGIN_DATA="$root/data" NIKA_PROGRESS_ONCE=1 \
      NIKA_PENDING_WATCH_ONCE=1 NIKA_PROGRESS_STATE="$root/progress.json" \
      NIKA_KIT_TIMEOUT_SECONDS=2 "$@" "$root/$tree/$script") >/dev/null 2>&1
    saw=no
    [ -e "$marker" ] && saw=yes
    if [ "$tree" = kit ]; then
      [ "$saw" = no ] && ok=yes || ok=no
      check "$label · the project's json.py and glob.py never run" "$ok" "$(cat "$marker" 2>/dev/null)"
    else
      [ "$saw" = yes ] && ok=yes || ok=no
      check "$label · control: without -I the same run imports them" "$ok" "no marker: this run never reached a python3 call"
    fi
  done
}

entry "session-context (session start)" yes \
  "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"s1\",\"cwd\":\"$p\"}" scripts/session-context.sh
entry "session-status (nika missing)" yes \
  "{\"session_id\":\"s2\",\"cwd\":\"$p\"}" scripts/session-status.sh PATH=/usr/bin:/bin
entry "stop-gate (escaped cwd)" yes \
  '{"session_id":"s3","cwd":"/nowhere"}' scripts/stop-gate.sh
entry "check-on-edit (a workflow edit)" yes \
  "{\"hook_event_name\":\"PostToolUse\",\"tool_input\":{\"file_path\":\"$p/flow.nika\"}}" scripts/check-on-edit.sh
entry "check-on-edit (a project file edit)" yes \
  "{\"hook_event_name\":\"PostToolUse\",\"tool_input\":{\"file_path\":\"$p/nika.yaml\"}}" scripts/check-on-edit.sh
entry "run-progress (monitor)" yes "" scripts/run-progress.sh
entry "pending-watch (monitor)" yes "" scripts/pending-watch.sh
entry "nika-facts (helper)" yes "" scripts/nika-facts.sh
entry "nika-pick-model (helper)" yes "" scripts/nika-pick-model.sh ANTHROPIC_API_KEY=placeholder-not-a-key
entry "intent-hint (prompt hook)" no '{"prompt":"make a workflow"}' scripts/intent-hint.sh
entry "guard-run (shell hook)" no "{\"command\":\"ls\",\"cwd\":\"$p\"}" scripts/guard-run.sh
entry "author-stop-gate (subagent stop)" no '{"agent_type":"nika:nika-author"}' scripts/author-stop-gate.py
entry "run-failed-hint (tool failure)" no '{}' scripts/run-failed-hint.py
entry "precompact-notes (compaction)" no "{\"session_id\":\"s4\",\"cwd\":\"$p\"}" scripts/precompact-notes.py

# 3. The host's environment. The planted modules sit outside the project,
# where only PYTHONPATH names them.
mkdir -p "$root/planted"
cp "$root/project/json.py" "$root/project/glob.py" "$root/planted/"
: >"$root/data/nika-session-h3"
home="$(env -i PATH="$root/stub:/usr/bin:/bin" python3 -I -c 'import sys; print(sys.base_prefix)')"
# hosted <script name>: whether a run reaches Python | its payload | extra env.
hosted() {
  case "$1" in
    session-context.sh) printf 'yes|{"hook_event_name":"SessionStart","session_id":"h1","cwd":"%s"}|\n' "$p" ;;
    session-status.sh) printf 'yes|{"session_id":"h2","cwd":"%s"}|PATH=/usr/bin:/bin\n' "$p" ;;
    stop-gate.sh) printf 'yes|{"session_id":"h3","cwd":"/nowhere"}|\n' ;;
    check-on-edit.sh) printf 'yes|{"hook_event_name":"PostToolUse","tool_input":{"file_path":"%s/flow.nika"}}|\n' "$p" ;;
    run-progress.sh | pending-watch.sh) printf 'yes||\n' ;;
    intent-hint.sh) printf 'no|{"prompt":"make a workflow"}|\n' ;;
    guard-run.sh) printf 'no|{"command":"ls","cwd":"%s"}|\n' "$p" ;;
    author-stop-gate.py) printf 'yes|{"agent_type":"nika:nika-author"}|\n' ;;
    run-failed-hint.py) printf 'yes|{}|\n' ;;
    precompact-notes.py) printf 'yes|{"session_id":"h4","cwd":"%s"}|\n' "$p" ;;
    *) return 1 ;;
  esac
}
commands="$(
  python3 -I - "$KIT" <<'PY'
import glob, json, os, sys
def walk(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "command" and isinstance(value, str):
                yield value
            else:
                yield from walk(value)
    elif isinstance(node, list):
        for value in node:
            yield from walk(value)
kit = sys.argv[1]
seen = []
for manifest in sorted(glob.glob(os.path.join(kit, "hooks", "*.json"))) + [os.path.join(kit, "monitors", "monitors.json")]:
    for command in walk(json.load(open(manifest, encoding="utf-8"))):
        if command not in seen:
            seen.append(command)
print("\n".join(seen))
PY
)"
count="$(printf '%s\n' "$commands" | grep -c .)"
[ "$count" -ge 10 ] && ok=yes || ok=no
check "the manifests name the hooks and monitors ($count commands)" "$ok" "too few commands read"
while IFS= read -r command; do
  [ -n "$command" ] || continue
  # The script is the command's last word: the hook itself, or the Python
  # script python-hook.sh is handed.
  script="${command##* }"
  script="${script##*/}"
  if ! row="$(hosted "$script")"; then
    check "$command · has a case here" no "add it to hosted() in this test"
    continue
  fi
  IFS="|" read -r reaches payload extra <<<"$row"
  for env_case in path home; do
    for tree in kit open; do
      [ "$tree" = open ] && [ "$reaches" = no ] && continue
      rm -f "$marker"
      # Hosts start hooks in the open project. A relative script (Cursor's
      # manifest) names one of the kit folder, spelled out here.
      run="$command"
      case "$run" in *' ./'*) run="${run%% ./*} \"$root/$tree\"/${run#* ./}" ;; esac
      set -- PYTHONPATH="$root/planted"
      [ "$env_case" = home ] && set -- "$@" PYTHONHOME="$home"
      [ -n "$extra" ] && set -- "$@" "$extra"
      (cd "$p" && printf '%s' "$payload" | env -i PATH="$root/stub:/usr/bin:/bin" \
        HOME="$root/home" TMPDIR="$root/tmp" CLAUDE_PLUGIN_DATA="$root/data" \
        CLAUDE_PLUGIN_ROOT="$root/$tree" NIKA_PROGRESS_ONCE=1 NIKA_PENDING_WATCH_ONCE=1 \
        NIKA_PROGRESS_STATE="$root/progress.json" NIKA_KIT_TIMEOUT_SECONDS=2 "$@" \
        /bin/sh -c "$run") >/dev/null 2>&1
      saw=no
      [ -e "$marker" ] && saw=yes
      label="$script · PYTHONPATH"
      [ "$env_case" = home ] && label="$label and PYTHONHOME"
      if [ "$tree" = kit ]; then
        [ "$saw" = no ] && ok=yes || ok=no
        check "$label · the planted json.py and glob.py never run" "$ok" "$(cat "$marker" 2>/dev/null)"
      else
        [ "$saw" = yes ] && ok=yes || ok=no
        check "$label · control: without -I and the restart they run" "$ok" "no marker: this run never reached Python"
      fi
    done
  done
done <<<"$commands"

if [ "$fails" -ne 0 ]; then
  printf 'FAIL  %s isolation control(s)\n' "$fails" >&2
  exit 1
fi
printf 'OK  the kit never imports from the open project; no workflow was run\n'
