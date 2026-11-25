#!/usr/bin/env bash
# guard-run.test.sh — the shim when its judge (the nika binary) is absent.
#
# The shim is the only part of the guard that runs when the judge does
# NOT. It cannot prove that an encoded or quoted command is unrelated,
# so it never reads the payload: it decides from where the hook runs.
#   - Inside a Nika project (nika.yaml or .nika/ in the host project
#     directory, the hook's working directory, or an ancestor): exit 2,
#     the hosts' shared blocking protocol, for every command.
#   - Elsewhere: the command goes through. The first call warns (exit 1,
#     stderr, no stdout), later calls answer the no-opinion {} until the
#     binary has been seen again.
# No command below is executed: payloads are data handed to the shim.
#
# Run with the binary genuinely absent — a PATH with a shell and nothing
# else — and with a temporary HOME and XDG_STATE_HOME, never the real ones.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHIM="$HERE/../guard-run.sh"
BARE_PATH="/usr/bin:/bin"
fails=0

# marked <dir>: print the nearest ancestor (or <dir>) carrying a marker.
marked() {
  local dir
  dir="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
  while :; do
    if [ -e "${dir%/}/nika.yaml" ] || [ -d "${dir%/}/.nika" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    [ "$dir" != / ] || return 1
    dir="${dir%/*}"
    [ -n "$dir" ] || dir=/
  done
}

# The outside cases mean something only if no ancestor of the scratch
# directory is itself a Nika project. A run leaves a .nika/ wherever it
# ran, the per-user temporary root included, so fall back to /tmp.
base=""
for candidate in "${TMPDIR:-/tmp}" /tmp; do
  if [ -d "$candidate" ] && ! marked "$candidate" >/dev/null; then
    base="$candidate"
    break
  fi
done
if [ -z "$base" ]; then
  printf 'FAIL  every temporary directory sits inside a Nika project (%s); set TMPDIR elsewhere\n' \
    "$(marked "${TMPDIR:-/tmp}")" >&2
  exit 1
fi
scratch="$(mktemp -d "${base%/}/guard-run-test.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
scratch="$(cd "$scratch" && pwd -P)"
home="$scratch/home"
state="$scratch/state"
marker="$state/nika/guard-off.warned"
mkdir -p "$home/.nika" "$home/work" "$scratch/outside" "$scratch/bin" \
  "$scratch/project/deep/er" "$scratch/store/.nika" "$scratch/store/sub"
: >"$scratch/project/nika.yaml"
# A judge that answers « no opinion », to bring the binary back.
printf '%s\n' '#!/bin/sh' '/bin/cat >/dev/null' "printf '{}'" >"$scratch/bin/nika"
chmod +x "$scratch/bin/nika"

# shim <dir> <payload> [NAME=value …] — run the shim from <dir>; sets rc out err.
# Later assignments override the defaults (env applies them in order).
shim() {
  local dir="$1" payload="$2"
  shift 2
  rc=0
  out="$(cd "$dir" && printf '%s' "$payload" | env -i PATH="$BARE_PATH" HOME="$home" \
    XDG_STATE_HOME="$state" "$@" /bin/bash "$SHIM" 2>"$scratch/stderr")" || rc=$?
  err="$(cat "$scratch/stderr")"
}

fail() {
  printf 'FAIL  %s — %s\n      rc=%s stdout=%s\n      stderr=%s\n' "$1" "$2" "$rc" "$out" "$err" >&2
  fails=$((fails + 1))
}

# blocked <name> <dir> <payload> [NAME=value …]
blocked() {
  local name="$1" dir="$2" payload="$3"
  shift 3
  shim "$dir" "$payload" "$@"
  if [ "$rc" -ne 2 ] || [ -n "$out" ] || [[ "$err" != *guard_unavailable* ]] \
    || [[ "$err" != *"this is a Nika project"* ]]; then
    fail "$name" 'want exit 2, no stdout, guard_unavailable naming the project'
  elif [ -e "$marker" ]; then
    fail "$name" 'a refusal must not consume the one warning'
  else
    printf 'ok    %s (blocked)\n' "$name"
  fi
}

# warned <name> <dir> [NAME=value …] — the first call outside a project.
warned() {
  local name="$1" dir="$2"
  shift 2
  shim "$dir" '{"command":"ls","cwd":"/tmp"}' "$@"
  if [ "$rc" -ne 1 ] || [ -n "$out" ] || [[ "$err" != *guard_off* ]] \
    || [[ "$err" != *"not on PATH"* ]] || [[ "$err" != *"brew install nika-open/tap/nika"* ]] \
    || [[ "$err" == *guard_unavailable* ]]; then
    fail "$name" 'want exit 1, no stdout, one guard_off warning with the repair'
  else
    printf 'ok    %s (warned, passes)\n' "$name"
  fi
}

# silent <name> <dir> <payload> [NAME=value …] — later calls outside a project.
silent() {
  local name="$1" dir="$2" payload="$3"
  shift 3
  shim "$dir" "$payload" "$@"
  if [ "$rc" -ne 0 ] || [ "$out" != '{}' ] || [ -n "$err" ]; then
    fail "$name" 'want exit 0, the no-opinion {}, nothing on stderr'
  else
    printf 'ok    %s (passes silently)\n' "$name"
  fi
}

payloads=(
  '{"command":"ls -la","cwd":"/tmp"}'
  '{"command":"git status","cwd":"/tmp"}'
  '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"/tmp"}'
  '{"command":"nika run x.nika","cwd":"/tmp"}'
  '{"command":"/opt/nika/bin/nika run x","cwd":"/tmp"}'
  '{"command":"sh -c \"nika run x\"","cwd":"/tmp"}'
  '{"command":"nika-cli run x","cwd":"/tmp"}'
  '{"command":"echo hi && nika run x","cwd":"/tmp"}'
  '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"nika run x"},"cwd":"/tmp"}'
  '{"command":"nika run x.yaml","cwd":"/tmp"}'
  '{"command":"n\\ika run x.yaml","cwd":"/tmp"}'
  '{"command":"echo hook_event_name; n\\ika run x.yaml","cwd":"/tmp"}'
  '{"hook_event_name":"PreToolUse","tool_input":{"command":"n\\ika run x.yaml"},"cwd":"/tmp"}'
)

# --- inside a Nika project: every payload refused, whatever it says -----
for i in "${!payloads[@]}"; do
  p="${payloads[$i]}"
  blocked "payload $i at a nika.yaml root" "$scratch/project" "$p"
  blocked "payload $i below a nika.yaml" "$scratch/project/deep/er" "$p"
  blocked "payload $i below a .nika/ store" "$scratch/store/sub" "$p"
  blocked "payload $i, Claude Code project dir" "$scratch/outside" "$p" \
    CLAUDE_PROJECT_DIR="$scratch/project"
  blocked "payload $i, Cursor project dir" "$scratch/outside" "$p" \
    CURSOR_PROJECT_DIR="$scratch/project/deep"
done
# The payload's own cwd is never evidence either way.
blocked 'a payload cwd outside the project' "$scratch/project" \
  "{\"command\":\"ls\",\"cwd\":\"$scratch/outside\"}"

# --- elsewhere: warn once, then pass silently ------------------------------
warned 'the first command outside a project' "$scratch/outside"
[ -e "$marker" ] || fail 'the warning marker' "want $marker written"
for i in "${!payloads[@]}"; do
  silent "payload $i outside, already warned" "$scratch/outside" "${payloads[$i]}"
done
silent 'the user-level ~/.nika is not a project' "$home/work" '{"command":"ls","cwd":"/tmp"}'
silent 'a payload cwd inside the project' "$scratch/outside" \
  "{\"command\":\"ls\",\"cwd\":\"$scratch/project\"}"

# --- the binary comes back, then leaves again: warn again ------------------
shim "$scratch/outside" '{"command":"ls","cwd":"/tmp"}' PATH="$scratch/bin:$BARE_PATH"
if [ "$rc" -ne 0 ] || [ "$out" != '{}' ] || [ -e "$marker" ]; then
  fail 'the binary back' 'want the judge verdict and the marker removed'
else
  printf 'ok    the binary back clears the warning marker\n'
fi
warned 'the binary gone again' "$scratch/outside"
silent 'the binary gone again, second command' "$scratch/outside" '{"command":"ls","cwd":"/tmp"}'

# --- the user-level ~/.nika alone never makes a project --------------------
rm -f "$marker"
warned 'the first command under HOME' "$home/work"

# --- no state directory to remember the warning: warn each time, never block
shim "$scratch/outside" '{"command":"ls","cwd":"/tmp"}' HOME= XDG_STATE_HOME=
first="$rc"
shim "$scratch/outside" '{"command":"ls","cwd":"/tmp"}' HOME= XDG_STATE_HOME=
if [ "$first" -ne 1 ] || [ "$rc" -ne 1 ] || [[ "$err" != *guard_off* ]]; then
  fail 'no state directory' 'want the warning (exit 1) on every call'
else
  printf 'ok    no state directory warns each time, never blocks\n'
fi

# --- exit 1 is a warning only while no manifest turns failures into blocks --
for manifest in "$HERE/../../hooks/claude-hooks.json" "$HERE/../../hooks/cursor-hooks.json"; do
  if grep -Eq '"(onFailure|failClosed)"' "$manifest"; then
    rc=- out=- err=-
    fail "$(basename "$manifest")" 'a failure policy would turn the warning into a refusal'
  else
    printf 'ok    %s sets no failure policy\n' "$(basename "$manifest")"
  fi
done

if [ "$fails" -gt 0 ]; then
  printf '\nFAIL  %d guard-run missing-binary case(s)\n' "$fails" >&2
  exit 1
fi

echo "OK  missing judge: refused inside a Nika project, warned once elsewhere, payload never read"
