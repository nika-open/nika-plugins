#!/usr/bin/env bash
# nika-on-path.test.sh: the repository never chooses the nika a hook runs.
#
# Hooks start in the open project, so a relative PATH entry (".", "bin",
# "node_modules/.bin", the empty one) and a relative NIKA_BIN both resolve
# inside it, and an absolute entry can name a folder inside it too, by its
# own path or through a link. Every kit hook and helper opens with the same
# nika-clean-path block, which keeps only the absolute entries whose real
# folder lies outside the project before anything else runs; this test
# keeps the copies identical and in front, then starts the hooks by their
# own path from the project, with the project's folders first on the PATH.
# The project is each of CLAUDE_PROJECT_DIR, CURSOR_PROJECT_DIR and the
# working folder, with the git work tree around each, never the home.
#
# A planted nika in the project records that it ran; a clean stub in an
# absolute folder stands in for the real binary. No workflow is run.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$(cd "$HERE/../.." && pwd)"
fails=0
check() {
  if [ "$2" = yes ]; then
    printf 'ok    %s\n' "$1"
  else
    printf 'FAIL  %s\n      %s\n' "$1" "$3" >&2
    fails=$((fails + 1))
  fi
}

# The block, byte for byte, in every bash hook and helper, and before any
# other line of code (only the shebang and comments come first).
block() { sed -n "/^$1 >>> nika-clean-path/,/^$1 <<< nika-clean-path/p" "$2"; }
first="$(block '#' "$KIT/scripts/guard-run.sh")"
[ -n "$first" ] && ok=yes || ok=no
check "guard-run carries the nika-clean-path block" "$ok" "no block in guard-run.sh"
for f in "$KIT"/scripts/*.sh "$KIT/bin/nika-kit"; do
  name="${f#"$KIT"/}"
  [ "$(block '#' "$f")" = "$first" ] && ok=yes || ok=no
  check "$name · the same nika-clean-path block" "$ok" "its block differs from guard-run.sh's or is missing"
  lead="$(sed -n '2,$p' "$f" | grep -v -e '^#' -e '^[[:space:]]*$' | head -n 1)"
  # shellcheck disable=SC2016 # the block's first line, literally
  [ "$lead" = 'nika_clean_path() {' ] && ok=yes || ok=no
  check "$name · the block runs before any other command" "$ok" "first line of code: $lead"
done
pyfirst="$(block '#' "$KIT/scripts/nika-verdict.py")"
isolated() { sed -n '/^# >>> nika-isolated/,/^# <<< nika-isolated/p' "$1"; }
pyiso="$(isolated "$KIT/scripts/nika-verdict.py")"
for f in "$KIT"/scripts/*.py; do
  name="${f#"$KIT"/}"
  [ -n "$pyfirst" ] && [ "$(block '#' "$f")" = "$pyfirst" ] && ok=yes || ok=no
  check "$name · the same Python nika-clean-path block" "$ok" "its block differs from nika-verdict.py's or is missing"
  [ -n "$pyiso" ] && [ "$(isolated "$f")" = "$pyiso" ] && ok=yes || ok=no
  check "$name · the same nika-isolated block" "$ok" "its block differs from nika-verdict.py's or is missing"
  # First the docstring, then the nika-isolated block before any import,
  # then imports only up to the nika-clean-path block: nothing that can run.
  lead="$(
    python3 -I - "$f" <<'EOF'
import ast, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
def at(marker):
    return next((n for n, line in enumerate(lines, 1) if line.startswith(marker)), 0)
start, end = at("# >>> nika-isolated:"), at("# <<< nika-isolated")
clean = at("# >>> nika-clean-path:")
nodes = [n for n in ast.parse("\n".join(lines)).body if n.lineno < clean]
docstring = bool(nodes) and isinstance(nodes[0], ast.Expr) and isinstance(nodes[0].value, ast.Constant)
if not (start and end and clean):
    print("a block marker is missing")
elif not docstring:
    print("the docstring is not first")
for node in nodes[1:] if docstring else []:
    inside = start < node.lineno < end
    if node.lineno < end and not inside:
        print(f"line {node.lineno}: {type(node).__name__} before the nika-isolated block")
        break
    if not inside and not isinstance(node, (ast.Import, ast.ImportFrom)):
        print(f"line {node.lineno}: {type(node).__name__} before the nika-clean-path block")
        break
EOF
  )"
  [ -z "$lead" ] && ok=yes || ok=no
  check "$name · the docstring, the nika-isolated block, then imports only" "$ok" "$lead"
done

for dir in /usr/bin /bin; do
  if [ -x "$dir/nika" ]; then
    # Nothing below could tell a planted nika from that one: fail, so a
    # skipped run is never read as a pass.
    echo "FAIL  SKIP nika-on-path.test: $dir holds a nika, so a PATH without the stub folder still finds one; the run cases did not run" >&2
    exit 1
  fi
done

root="$(mktemp -d)"
root="$(cd "$root" && pwd -P)"
trap 'rm -rf "$root"' EXIT
p="$root/project"
mkdir -p "$root/clean" "$root/home" "$root/state" "$root/tmp" "$p/bin" "$p/node_modules/.bin" \
  "$root/elsewhere" "$p/.claude/hooks-nika" "$p/.nika/traces"
for planted in "$p/bin/nika" "$p/nika" "$p/node_modules/.bin/nika"; do
  cat >"$planted" <<EOF
#!/bin/sh
echo "\$0" >>"$root/planted-ran"
printf '{}\n'
EOF
  chmod +x "$planted"
done
cat >"$root/clean/nika" <<EOF
#!/bin/sh
echo "\$1" >>"$root/clean-ran"
case "\$1" in
  --version) echo "nika 0.0.0 (clean stub)" ;;
  guard) /bin/cat >/dev/null; printf '{}\n' ;;
  trace) printf '{"traces":[]}' ;;
esac
exit 0
EOF
chmod +x "$root/clean/nika"
printf 'nika: flow\ntasks: {}\n' >"$p/flow.nika"
for hook in check-on-edit session-context; do
  sed 's|^resolver="../bin/nika-kit"$|resolver=""|' "$KIT/scripts/$hook.sh" \
    >"$p/.claude/hooks-nika/$hook.sh"
  chmod +x "$p/.claude/hooks-nika/$hook.sh"
done
relative="bin:.::node_modules/.bin"

# run <cwd> <stdin> <script> [VAR=value...]: starts the script by its own
# path, as a host does, with $arg as its one argument when set; writes
# $root/out, err, rc.
arg=""
run() {
  local cwd="$1" payload="$2" script="$3" rc=0
  shift 3
  rm -f "$root/planted-ran" "$root/clean-ran"
  (cd "$cwd" && printf '%s' "$payload" | env -i HOME="$root/home" XDG_STATE_HOME="$root/state" \
    TMPDIR="$root/tmp" CLAUDE_PLUGIN_DATA="$root/state" "$@" "$script" ${arg:+"$arg"}) >"$root/out" 2>"$root/err" || rc=$?
  printf '%s\n' "$rc" >"$root/rc"
}
planted_quiet() { [ ! -e "$root/planted-ran" ]; }
ran() { grep -qx -e "$1" "$root/clean-ran" 2>/dev/null; }

# The run guard.
run "$p" "{\"command\":\"ls\",\"cwd\":\"$p\"}" "$KIT/scripts/guard-run.sh" \
  PATH="$relative:$root/clean:/usr/bin:/bin"
[ "$(cat "$root/rc")" = 0 ] && [ "$(cat "$root/out")" = '{}' ] && ran guard && ok=yes || ok=no
check "guard-run · relative PATH folders first: the stub in the absolute folder judges" "$ok" "rc=$(cat "$root/rc") out=$(cat "$root/out")"
planted_quiet && ok=yes || ok=no
check "guard-run · the project's nika never runs" "$ok" "ran: $(cat "$root/planted-ran" 2>/dev/null)"
run "$root/elsewhere" "{\"command\":\"ls\",\"cwd\":\"$root/elsewhere\"}" "$KIT/scripts/guard-run.sh" \
  PATH="$p/bin:$p:/usr/bin:/bin"
[ -e "$root/planted-ran" ] && ok=yes || ok=no
check "guard-run · control: an absolute PATH folder is searched (its nika runs)" "$ok" "an absolute folder holding nika was not searched"
run "$p" '{"command":"ls"}' "$KIT/scripts/guard-run.sh" PATH="$relative:/usr/bin:/bin"
# Missing: a warning outside a Nika project (exit 1), a refusal inside one
# (exit 2; the project's .nika/ folder makes one).
case "$(cat "$root/rc")" in 1 | 2) ok=yes ;; *) ok=no ;; esac
grep -q 'the nika binary is not on PATH' "$root/err" && planted_quiet || ok=no
check "guard-run · a nika only in relative folders counts as missing" "$ok" "rc=$(cat "$root/rc") err=$(cat "$root/err")"
rm -f "$root/state/nika/guard-off.warned"

# The edit hook, in the plugin (it asks the kit resolver) and as the copy
# `nika init` writes (its resolver line emptied).
payload="{\"hook_event_name\":\"PostToolUse\",\"tool_input\":{\"file_path\":\"$p/flow.nika\"}}"
for where in plugin copy; do
  script="$KIT/scripts/check-on-edit.sh"
  [ "$where" = copy ] && script="$p/.claude/hooks-nika/check-on-edit.sh"
  run "$p" "$payload" "$script" PATH="$relative:$root/clean:/usr/bin:/bin" NIKA_CHECK_ANNOUNCE_CLEAN=1
  grep -q "clean · $root/clean/nika " "$root/err" && ok=yes || ok=no
  check "check-on-edit ($where) · relative PATH folders first: the absolute folder's nika judges" "$ok" "err=$(cat "$root/err")"
  planted_quiet && ok=yes || ok=no
  check "check-on-edit ($where) · the project's nika never runs" "$ok" "ran: $(cat "$root/planted-ran" 2>/dev/null)"
  run "$p" "$payload" "$script" PATH="$relative:$root/clean:/usr/bin:/bin" NIKA_CHECK_ANNOUNCE_CLEAN=1 \
    NIKA_BIN=bin/nika
  grep -q 'NIKA_BIN is not an absolute path' "$root/err" && grep -q "clean · $root/clean/nika " "$root/err" \
    && planted_quiet && ok=yes || ok=no
  check "check-on-edit ($where) · a relative NIKA_BIN is set aside, said once on stderr" "$ok" "err=$(cat "$root/err") ran: $(cat "$root/planted-ran" 2>/dev/null)"
done

# The session hooks: the context seed (plugin and project copy) probes and
# runs one nika for its version handshake; the status hook lists waiting
# runs through the Python helper.
start="{\"hook_event_name\":\"SessionStart\",\"session_id\":\"s1\",\"cwd\":\"$p\"}"
for where in plugin copy; do
  script="$KIT/scripts/session-context.sh"
  [ "$where" = copy ] && script="$p/.claude/hooks-nika/session-context.sh"
  run "$p" "$start" "$script" PATH="$relative:$root/clean:/usr/bin:/bin"
  grep -q 'Workspace root' "$root/out" && ran --version && ok=yes || ok=no
  check "session-context ($where) · the absolute folder's nika gives the version" "$ok" "out=$(head -c 200 "$root/out") ran=$(cat "$root/clean-ran" 2>/dev/null)"
  planted_quiet && ok=yes || ok=no
  check "session-context ($where) · the project's nika never runs" "$ok" "ran: $(cat "$root/planted-ran" 2>/dev/null)"
  run "$p" "$start" "$script" PATH="$relative:/usr/bin:/bin"
  grep -q 'the nika binary is not on PATH' "$root/out" && planted_quiet && ok=yes || ok=no
  check "session-context ($where) · a nika only in relative folders counts as missing" "$ok" "out=$(head -c 200 "$root/out") ran: $(cat "$root/planted-ran" 2>/dev/null)"
done
run "$p" "$start" "$KIT/scripts/session-status.sh" PATH="$relative:$root/clean:/usr/bin:/bin"
[ "$(cat "$root/rc")" = 0 ] && ran trace && planted_quiet && ok=yes || ok=no
check "session-status · waiting runs are listed with the absolute folder's nika" "$ok" "rc=$(cat "$root/rc") ran=$(cat "$root/clean-ran" 2>/dev/null) planted: $(cat "$root/planted-ran" 2>/dev/null)"
run "$p" "$start" "$KIT/scripts/session-status.sh" PATH="$relative:/usr/bin:/bin"
grep -q 'the nika program is not on PATH' "$root/out" && planted_quiet && ok=yes || ok=no
check "session-status · a nika only in relative folders counts as missing" "$ok" "out=$(head -c 200 "$root/out") ran: $(cat "$root/planted-ran" 2>/dev/null)"

# The Python helpers: the author gate checks the workflow it was handed
# with the kit's nika, and with none there is no binary, never a search of
# the project's folders.
gate="{\"agent_type\":\"nika-author\",\"cwd\":\"$p\",\"last_assistant_message\":\"Wrote flow.nika\"}"
run "$p" "$gate" "$KIT/scripts/author-stop-gate.py" PATH="$relative:$root/clean:/usr/bin:/bin"
ran check && planted_quiet && ok=yes || ok=no
check "author-stop-gate · the workflow is checked by the absolute folder's nika" "$ok" "rc=$(cat "$root/rc") ran=$(cat "$root/clean-ran" 2>/dev/null) planted: $(cat "$root/planted-ran" 2>/dev/null) err=$(head -c 300 "$root/err")"
run "$p" "$gate" "$KIT/scripts/author-stop-gate.py" PATH="$relative:/usr/bin:/bin"
grep -q 'no nika binary was found' "$root/out" "$root/err" && planted_quiet && ok=yes || ok=no
check "author-stop-gate · a nika only in relative folders counts as missing" "$ok" "out=$(head -c 300 "$root/out") err=$(head -c 300 "$root/err") ran: $(cat "$root/planted-ran" 2>/dev/null)"
arg="$p/flow.nika"
run "$p" "" "$KIT/scripts/nika-verdict.py" PATH="$relative:/usr/bin:/bin" NIKA_BIN=bin/nika
arg=""
[ "$(cat "$root/rc")" = 127 ] && grep -q 'nika is not installed' "$root/out" && planted_quiet && ok=yes || ok=no
check "nika-verdict · no absolute nika and a relative NIKA_BIN: no binary, the project's never runs" "$ok" "rc=$(cat "$root/rc") out=$(head -c 200 "$root/out") ran: $(cat "$root/planted-ran" 2>/dev/null)"

# The kit resolver.
out="$( (cd "$p" && env -i HOME="$root/home" PATH="$relative:$root/clean:/usr/bin:/bin" "$KIT/bin/nika-kit" --path) 2>/dev/null)"
[ "$out" = "$root/clean/nika" ] && ok=yes || ok=no
check "nika-kit · relative PATH folders first: names the absolute folder's nika" "$ok" "named: $out"
out="$( (cd "$p" && env -i HOME="$root/home" PATH="$root/clean:/usr/bin:/bin" NIKA_BIN=bin/nika "$KIT/bin/nika-kit" --path) 2>"$root/err")"
rc=$?
[ "$rc" = 1 ] && [ -z "$out" ] && grep -q 'NIKA_BIN is not an absolute path' "$root/err" && ok=yes || ok=no
check "nika-kit · a relative NIKA_BIN is an error, never a fall back" "$ok" "rc=$rc out=$out err=$(cat "$root/err")"

# Absolute PATH entries that lead into the project. The project's
# node_modules/.bin holds a planted nika and a planted cat, both named by an
# absolute entry first on the PATH; each case names the project another
# way. A second project, g, is a git work tree started from a subfolder.
g="$root/g"
mkdir -p "$g/.git" "$g/sub" "$g/node_modules/.bin" "$root/links" "$root/home/bin"
for planted in "$p/node_modules/.bin/cat" "$g/node_modules/.bin/cat" "$g/node_modules/.bin/nika"; do
  cat >"$planted" <<EOF
#!/bin/sh
echo "\$0" >>"$root/planted-ran"
exec /bin/cat "\$@"
EOF
  chmod +x "$planted"
done
cp "$p/node_modules/.bin/nika" "$g/node_modules/.bin/nika"
printf 'nika: flow\ntasks: {}\n' >"$g/flow.nika"
ln -s "$p/node_modules/.bin" "$root/links/tools"
cp "$root/clean/nika" "$root/home/bin/nika"
guard_cmd="{\"command\":\"ls\",\"cwd\":\"$p\"}"
inside="$p/node_modules/.bin:$root/clean:/usr/bin:/bin"
# absolute <label> <cwd> <PATH> [VAR=value...]: the guard and the edit hook
# judge with the clean stub; neither planted program runs.
absolute() {
  local label="$1" cwd="$2" path="$3" edit
  shift 3
  edit="{\"hook_event_name\":\"PostToolUse\",\"tool_input\":{\"file_path\":\"$cwd/flow.nika\"}}"
  [ -e "$cwd/flow.nika" ] || edit="{\"hook_event_name\":\"PostToolUse\",\"tool_input\":{\"file_path\":\"$p/flow.nika\"}}"
  run "$cwd" "$guard_cmd" "$KIT/scripts/guard-run.sh" PATH="$path" "$@"
  [ "$(cat "$root/rc")" = 0 ] && [ "$(cat "$root/out")" = '{}' ] && ran guard && planted_quiet && ok=yes || ok=no
  check "guard-run · $label: the clean nika judges, the planted one never runs" "$ok" "rc=$(cat "$root/rc") out=$(cat "$root/out") ran: $(cat "$root/planted-ran" 2>/dev/null)"
  run "$cwd" "$edit" "$KIT/scripts/check-on-edit.sh" PATH="$path" NIKA_CHECK_ANNOUNCE_CLEAN=1 "$@"
  grep -q "clean · $root/clean/nika " "$root/err" && planted_quiet && ok=yes || ok=no
  check "check-on-edit · $label: neither the planted nika nor the planted cat runs" "$ok" "err=$(head -c 300 "$root/err") ran: $(cat "$root/planted-ran" 2>/dev/null)"
}
absolute "the working folder" "$p" "$inside"
absolute "CLAUDE_PROJECT_DIR" "$root/elsewhere" "$inside" CLAUDE_PROJECT_DIR="$p"
absolute "CURSOR_PROJECT_DIR" "$root/elsewhere" "$inside" CURSOR_PROJECT_DIR="$p"
absolute "a link to the project's folder" "$root/elsewhere" "$root/links/tools:$root/clean:/usr/bin:/bin" CLAUDE_PROJECT_DIR="$p"
absolute "the git work tree, from a subfolder" "$g/sub" "$g/node_modules/.bin:$root/clean:/usr/bin:/bin"
# Control: from a folder that is not the project, the same absolute entry
# is kept, so both planted programs are reachable and the cases above
# prove something.
run "$root/elsewhere" "{\"command\":\"ls\",\"cwd\":\"$root/elsewhere\"}" "$KIT/scripts/guard-run.sh" PATH="$inside"
grep -qx "$p/node_modules/.bin/nika" "$root/planted-ran" 2>/dev/null && ok=yes || ok=no
check "guard-run · control: outside the project its absolute folder is searched (the planted nika runs)" "$ok" "ran: $(cat "$root/planted-ran" 2>/dev/null)"
run "$root/elsewhere" "{\"hook_event_name\":\"PostToolUse\",\"tool_input\":{\"file_path\":\"$p/flow.nika\"}}" \
  "$KIT/scripts/check-on-edit.sh" PATH="$inside"
grep -qx "$p/node_modules/.bin/cat" "$root/planted-ran" 2>/dev/null && ok=yes || ok=no
check "check-on-edit · control: outside the project the planted cat runs" "$ok" "ran: $(cat "$root/planted-ran" 2>/dev/null)"
# The home is never the project: a project folder that is the home keeps
# the home's own bin, where this stub nika sits.
run "$root/home" "{\"command\":\"ls\",\"cwd\":\"$root/home\"}" "$KIT/scripts/guard-run.sh" \
  PATH="$root/home/bin:/usr/bin:/bin" CLAUDE_PROJECT_DIR="$root/home"
[ "$(cat "$root/rc")" = 0 ] && ran guard && ok=yes || ok=no
check "guard-run · a project folder that is the home keeps the home's own PATH folders" "$ok" "rc=$(cat "$root/rc") err=$(head -c 300 "$root/err")"
# The Python block and the kit resolver drop the same entries. A Python
# hook starts the kit resolver as `bash`, by name, so the project's
# node_modules/.bin holds a planted bash for these cases.
for planted in "$p/node_modules/.bin/bash" "$g/node_modules/.bin/bash"; do
  cat >"$planted" <<EOF
#!/bin/sh
echo "\$0" >>"$root/planted-ran"
exec /bin/bash "\$@"
EOF
  chmod +x "$planted"
done
run "$root/elsewhere" "$gate" "$KIT/scripts/author-stop-gate.py" PATH="$inside" CLAUDE_PROJECT_DIR="$p"
ran check && planted_quiet && ok=yes || ok=no
check "author-stop-gate · CLAUDE_PROJECT_DIR: the clean nika checks, the planted one never runs" "$ok" "ran=$(cat "$root/clean-ran" 2>/dev/null) planted: $(cat "$root/planted-ran" 2>/dev/null) err=$(head -c 300 "$root/err")"
gate_g="{\"agent_type\":\"nika-author\",\"cwd\":\"$g\",\"last_assistant_message\":\"Wrote flow.nika\"}"
run "$g/sub" "$gate_g" "$KIT/scripts/author-stop-gate.py" PATH="$g/node_modules/.bin:$root/clean:/usr/bin:/bin"
ran check && planted_quiet && ok=yes || ok=no
check "author-stop-gate · the git work tree: the clean nika checks, the planted one never runs" "$ok" "ran=$(cat "$root/clean-ran" 2>/dev/null) planted: $(cat "$root/planted-ran" 2>/dev/null) err=$(head -c 300 "$root/err")"
# Control: from a folder that is not the project, the Python hook starts the
# planted bash, so the two cases above prove something.
run "$root/elsewhere" "$gate" "$KIT/scripts/author-stop-gate.py" PATH="$inside"
grep -qx "$p/node_modules/.bin/bash" "$root/planted-ran" 2>/dev/null && ok=yes || ok=no
check "author-stop-gate · control: outside the project the planted bash runs" "$ok" "ran: $(cat "$root/planted-ran" 2>/dev/null)"
rm -f "$p/node_modules/.bin/bash" "$g/node_modules/.bin/bash"
out="$( (cd "$root/elsewhere" && env -i HOME="$root/home" CLAUDE_PROJECT_DIR="$p" \
  PATH="$root/links/tools:$root/clean:/usr/bin:/bin" "$KIT/bin/nika-kit" --path) 2>/dev/null)"
[ "$out" = "$root/clean/nika" ] && ok=yes || ok=no
check "nika-kit · a link to the project's folder first: names the clean nika" "$ok" "named: $out"

# nika_on_path alone, with no block before it: `type -P` answers a relative
# path for a relative PATH entry, and the function names no nika then. The
# block drops those entries first, so this is the last line, tested apart.
fn="$(awk '/^nika_on_path\(\) \{$/ { on = 1 } on { print } on && /^}$/ { exit }' "$KIT/scripts/guard-run.sh")"
mkdir -p "$root/rel/bin"
cp "$root/clean/nika" "$root/rel/bin/nika"
# shellcheck disable=SC2016 # expanded by the inner bash
out="$(cd "$root/rel" && env -i PATH="bin:/usr/bin:/bin" FN="$fn" /bin/bash -p -c 'eval "$FN"; nika_on_path; echo "rc=$?"')"
[ "$out" = "rc=1" ] && ok=yes || ok=no
check "nika_on_path · a relative answer of type -P names no nika" "$ok" "out=$out"
# shellcheck disable=SC2016 # expanded by the inner bash
out="$(cd "$root/rel" && env -i PATH="$root/rel/bin:/usr/bin:/bin" FN="$fn" /bin/bash -p -c 'eval "$FN"; nika_on_path; echo "rc=$?"')"
[ "$out" = "$root/rel/bin/nika
rc=0" ] && ok=yes || ok=no
check "nika_on_path · control: an absolute folder's nika is named" "$ok" "out=$out"

if [ "$fails" -ne 0 ]; then
  printf 'FAIL  %s binary-choice control(s)\n' "$fails" >&2
  exit 1
fi
printf 'OK  no hook runs a nika the repository placed; no workflow was run\n'
