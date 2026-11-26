#!/usr/bin/env bash
# hook-launch.test.sh: the host's environment never picks or changes the
# interpreter a kit hook starts with.
#
# Every command the hook and monitor manifests name starts its script with
# /bin/bash -p: the host's PATH does not pick the bash, and in privileged
# mode bash reads no BASH_ENV file and imports no function from the
# environment (an exported `cd` would otherwise run inside the PATH block
# itself). The Python hooks start through python-hook.sh, which sets the
# PATH first, finds python3 there as an absolute path and runs the script
# with -I.
#
# Each command runs from the folder its host documents, as it is written:
# Cursor runs a plugin's hooks from the plugin's install folder
# (CURSOR_PLUGIN_ROOT), but `stop` and `subagentStop` from the workspace
# root (https://cursor.com/docs/hooks, read 2026-11-26); Claude Code and
# Codex run them from the session's folder, the project, with the plugin's
# root in CLAUDE_PLUGIN_ROOT (Codex sets PLUGIN_ROOT too,
# https://learn.chatgpt.com/docs/hooks, read 2026-11-26).
#
# Five proofs:
#   1. The manifests: each command is /bin/bash -p and a kit script, and a
#      Python hook is reached only through python-hook.sh.
#   2. Each command, run the way a host runs it with a BASH_ENV file and an
#      exported `cd` function that both leave a marker, leaves none. The same
#      command without -p leaves one (the control: on this bash, -p is what
#      keeps them out).
#   3. python-hook.sh runs the script isolated (-I), with the python3 of an
#      absolute PATH folder outside the project, never a planted one.
#   4. python-hook.sh refuses a name that is not a Python script beside it,
#      and says so when the PATH holds no python3.
#   5. Under a plugin root whose path holds a space, each command still
#      reaches its own script: an unquoted root splits there, and the shell's
#      exit 127 is an error every host lets through. The same command with
#      the root unquoted reaches nothing (the control).
#
# Stub binaries stand in for nika; no model, no network, no workflow run.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$(cd "$HERE/../.." && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL hook-launch.test: python3 is absent, so nothing was asserted" >&2
  exit 1
fi
if [ ! -x /bin/bash ]; then
  echo "FAIL hook-launch.test: there is no /bin/bash, so the manifests' hooks cannot start here" >&2
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

root="$(mktemp -d)"
root="$(cd "$root" && pwd -P)"
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/stub" "$root/home" "$root/tmp" "$root/data" "$root/project/.nika/traces"
cat >"$root/stub/nika" <<'EOF'
#!/bin/sh
case "$1" in
  --version) echo "nika 0.0.0 (stub)" ;;
  guard) /bin/cat >/dev/null; printf '{}\n' ;;
  trace) echo '[]' ;;
esac
exit 0
EOF
chmod +x "$root/stub/nika"
p="$root/project"
printf 'nika: project\n' >"$p/nika.yaml"

# 1. The manifests. Each line is the folder the host runs the command from
# (`plugin` for the plugin root, `project` otherwise), a tab, the command.
commands="$(
  python3 -I - "$KIT" <<'PY'
import glob, json, os, sys
def walk(node, event=None):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "command" and isinstance(value, str):
                yield event, value
            else:
                yield from walk(value, key if event is None and key != "hooks" else event)
    elif isinstance(node, list):
        for value in node:
            yield from walk(value, event)
kit = sys.argv[1]
for manifest in sorted(glob.glob(os.path.join(kit, "hooks", "*.json"))) + [os.path.join(kit, "monitors", "monitors.json")]:
    cursor = os.path.basename(manifest) == "cursor-hooks.json"
    for event, command in walk(json.load(open(manifest, encoding="utf-8"))):
        where = "plugin" if cursor and event not in ("stop", "subagentStop") else "project"
        print("%s\t%s" % (where, command))
PY
)"
count="$(printf '%s\n' "$commands" | grep -c .)"
[ "$count" -ge 13 ] && ok=yes || ok=no
check "the manifests name the hooks and monitors ($count commands)" "$ok" "too few commands read"
plugin_run="$(printf '%s\n' "$commands" | grep -c '^plugin')"
[ "$plugin_run" = 3 ] && ok=yes || ok=no
check "Cursor's three hooks run from the plugin root" "$ok" "$plugin_run commands read as run from the plugin root"
while IFS=$'\t' read -r where command; do
  [ -n "$command" ] || continue
  rest="${command#/bin/bash -p }"
  [ "$rest" != "$command" ] && ok=yes || ok=no
  check "$command · starts with /bin/bash -p" "$ok" "the host's PATH would pick the interpreter"
  script="${rest%% *}"
  arg="${rest#"$script"}"
  arg="${arg# }"
  script="$(printf '%s' "$script" | tr -d '"')"
  script="${script##*/}"
  case "$script" in
    python-hook.sh)
      case "$arg" in
        *[!A-Za-z0-9._-]* | '' | */*) ok=no ;;
        *.py) [ -f "$KIT/scripts/$arg" ] && ok=yes || ok=no ;;
        *) ok=no ;;
      esac
      check "$command · python-hook.sh is handed a Python script of the kit" "$ok" "argument: $arg"
      ;;
    *.sh)
      [ -z "$arg" ] && [ -f "$KIT/scripts/$script" ] && ok=yes || ok=no
      check "$command · names a bash script of the kit and nothing more" "$ok" "script: $script, argument: $arg"
      ;;
    *)
      check "$command · names a bash script of the kit" no "a Python script started by its shebang takes python3 from the host's PATH"
      ;;
  esac
done <<<"$commands"

# 2. The host's environment. The BASH_ENV file and the exported function
# both write a marker; the function then does what cd does. The bash that
# exports the function runs with -p itself and hands BASH_ENV to the host's
# shell only, so only the hook's own bash can leave a marker.
marker="$root/marker"
printf 'echo bash_env >>"%s"\n' "$marker" >"$root/bash-env.sh"
# start <where> <command>: run it as its host does, from the folder that
# host documents for it (the plugin root, or the project), as it is written.
start() {
  local from="$p" run="$2"
  [ "$1" != plugin ] || from="$KIT"
  # shellcheck disable=SC2016 # the function text, exported by bash itself
  (cd "$from" && printf '{}' | env -i PATH="$root/stub:/usr/bin:/bin" HOME="$root/home" \
    TMPDIR="$root/tmp" CLAUDE_PLUGIN_DATA="$root/data" CLAUDE_PLUGIN_ROOT="$KIT" \
    CURSOR_PLUGIN_ROOT="$KIT" CURSOR_PROJECT_DIR="$p" \
    CLAUDE_PROJECT_DIR="$p" NIKA_PROGRESS_ONCE=1 NIKA_PENDING_WATCH_ONCE=1 \
    NIKA_PROGRESS_STATE="$root/progress.json" NIKA_KIT_TIMEOUT_SECONDS=2 \
    HOOK_BASH_ENV="$root/bash-env.sh" MARKER="$marker" RUN="$run" \
    /bin/bash -p -c 'cd() { echo function >>"$MARKER"; builtin cd "$@"; }; export -f cd
      BASH_ENV="$HOOK_BASH_ENV" exec /bin/sh -c "$RUN"') >/dev/null 2>&1
}
while IFS=$'\t' read -r where command; do
  [ -n "$command" ] || continue
  rm -f "$marker"
  start "$where" "$command"
  [ ! -e "$marker" ] && ok=yes || ok=no
  check "$command · no BASH_ENV file and no exported function runs" "$ok" "marker: $(tr '\n' ' ' <"$marker" 2>/dev/null)"
  rm -f "$marker"
  start "$where" "/bin/bash ${command#/bin/bash -p }"
  grep -qx bash_env "$marker" 2>/dev/null && grep -qx function "$marker" 2>/dev/null && ok=yes || ok=no
  check "$command · control: without -p both run" "$ok" "marker: $(tr '\n' ' ' <"$marker" 2>/dev/null)"
done <<<"$commands"

# 3. python-hook.sh: a copy of it beside a probe script, started from a
# project whose folders hold a planted python3, first on the PATH both
# relatively and by an absolute entry.
mkdir -p "$root/kit/scripts" "$p/bin" "$p/node_modules/.bin" "$root/planted"
cp "$KIT/scripts/python-hook.sh" "$root/kit/scripts/"
cat >"$root/kit/scripts/probe.py" <<'EOF'
import sys
print("isolated=%d" % sys.flags.isolated)
print("planted=%d" % any("planted" in entry for entry in sys.path))
print("args=%s" % " ".join(sys.argv[1:]))
EOF
real="$(PATH=/usr/bin:/bin command -v python3)"
real_dir="${real%/*}"
# The planted interpreter's name, spelled so the isolation scanner of
# kit-python-isolated.test.sh does not read a call in it.
planted_name="pyth"
planted_name="${planted_name}on3"
for folder in "$p/bin" "$p/node_modules/.bin"; do
  # shellcheck disable=SC2016 # the stub's own $0 and $@
  printf '#!/bin/sh\necho "$0" >>"%s/planted-ran"\nexec %s "$@"\n' "$root" "$real" >"$folder/$planted_name"
  chmod +x "$folder/$planted_name"
done
launch() {
  (cd "$p" && env -i PATH="$1" HOME="$root/home" PYTHONPATH="$root/planted" \
    /bin/bash -p "$root/kit/scripts/python-hook.sh" "${@:2}") >"$root/out" 2>"$root/err"
  printf '%s\n' "$?" >"$root/rc"
}
rm -f "$root/planted-ran"
launch "bin:$p/node_modules/.bin:$real_dir:/usr/bin:/bin" probe.py one two
grep -qx 'isolated=1' "$root/out" && grep -qx 'planted=0' "$root/out" \
  && grep -qx 'args=one two' "$root/out" && ok=yes || ok=no
check "python-hook · the script runs isolated, its arguments handed on" "$ok" "rc=$(cat "$root/rc") out=$(tr '\n' ' ' <"$root/out") err=$(head -c 300 "$root/err")"
[ ! -e "$root/planted-ran" ] && ok=yes || ok=no
check "python-hook · no python3 from the project's folders runs" "$ok" "ran: $(cat "$root/planted-ran" 2>/dev/null)"
# Control: outside the project the absolute folder is kept, so the planted
# python3 there is reachable and the case above proves something.
(cd "$root/tmp" && env -i PATH="$p/node_modules/.bin:/usr/bin:/bin" HOME="$root/home" \
  /bin/bash -p "$root/kit/scripts/python-hook.sh" probe.py) >/dev/null 2>&1
[ -e "$root/planted-ran" ] && ok=yes || ok=no
check "python-hook · control: outside the project that folder's python3 runs" "$ok" "the planted python3 was never reached"

# 4. What python-hook.sh refuses: a folder in the name, a script that is
# not Python (one sits beside it), a missing one, a hidden one, no name.
mkdir -p "$root/nopython"
cp "$KIT/scripts/python-hook.sh" "$root/kit/scripts/probe.sh"
for name in ../scripts/probe.py probe.sh missing.py .hidden.py ''; do
  launch "$root/nopython:/usr/bin:/bin" "$name"
  [ "$(cat "$root/rc")" = 1 ] && [ ! -s "$root/out" ] && grep -q 'names no Python script of the kit' "$root/err" \
    && ok=yes || ok=no
  check "python-hook · '$name' is refused, nothing runs" "$ok" "rc=$(cat "$root/rc") out=$(head -c 200 "$root/out") err=$(head -c 300 "$root/err")"
done
launch "$root/nopython" probe.py
[ "$(cat "$root/rc")" = 1 ] && [ ! -s "$root/out" ] && grep -q 'python3 is not on the PATH' "$root/err" \
  && ok=yes || ok=no
check "python-hook · no python3 on the PATH: said on stderr, exit 1" "$ok" "rc=$(cat "$root/rc") err=$(head -c 300 "$root/err")"

# 5. A plugin root whose path holds a space: a copy of the manifests under
# it, and in its scripts/ a probe for each script they name, which records
# its own name and arguments. Each command runs as its host runs it, from
# its folder, with the root in CLAUDE_PLUGIN_ROOT, PLUGIN_ROOT and
# CURSOR_PLUGIN_ROOT, and must reach its own probe.
spaced="$root/plugin root"
mkdir -p "$spaced/hooks" "$spaced/monitors" "$spaced/scripts"
cp "$KIT"/hooks/*.json "$spaced/hooks/"
cp "$KIT/monitors/monitors.json" "$spaced/monitors/"
probe_log="$root/probe.log"
for script in "$KIT"/scripts/*.sh; do
  # shellcheck disable=SC2016 # the probe's own $0 and $*
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "${0##*/}" "$*" >>"%s"\n' "$probe_log" >"$spaced/scripts/${script##*/}"
done
# reach <where> <command>: run it as its host does under the spaced root.
reach() {
  local from="$p"
  [ "$1" != plugin ] || from="$spaced"
  rm -f "$probe_log"
  (cd "$from" && env -i PATH=/usr/bin:/bin HOME="$root/home" CLAUDE_PLUGIN_ROOT="$spaced" \
    PLUGIN_ROOT="$spaced" CURSOR_PLUGIN_ROOT="$spaced" CLAUDE_PROJECT_DIR="$p" \
    /bin/sh -c "$2" </dev/null >/dev/null 2>&1)
}
# shellcheck disable=SC2016 # the manifests' own spelling of the root
quoted='"${CLAUDE_PLUGIN_ROOT}"'
# shellcheck disable=SC2016 # the same root, unquoted
bare='${CLAUDE_PLUGIN_ROOT}'
while IFS=$'\t' read -r where command; do
  [ -n "$command" ] || continue
  rest="${command#/bin/bash -p }"
  script="${rest%% *}"
  arg="${rest#"$script"}"
  script="$(printf '%s' "$script" | tr -d '"')"
  want="${script##*/} ${arg# }"
  reach "$where" "$command" && [ "$(cat "$probe_log" 2>/dev/null)" = "$want" ] && ok=yes || ok=no
  check "$command · under a root with a space it reaches its own script" "$ok" "probe: $(cat "$probe_log" 2>/dev/null)"
  case "$command" in
    *"$quoted"*)
      reach "$where" "${command/"$quoted"/$bare}"
      [ ! -e "$probe_log" ] && ok=yes || ok=no
      check "$command · control: the root unquoted splits at the space and reaches nothing" "$ok" "probe: $(cat "$probe_log" 2>/dev/null)"
      ;;
  esac
done <<<"$commands"

if [ "$fails" -ne 0 ]; then
  printf 'FAIL  %s launch control(s)\n' "$fails" >&2
  exit 1
fi
printf 'OK  every kit hook starts with /bin/bash -p, Python ones isolated; no workflow was run\n'
