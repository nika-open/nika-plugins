#!/usr/bin/env bash
# check-on-edit — the plugin's seatbelt: after the agent edits a
# *.nika, run the audit so findings reach the agent immediately
# (the file is the contract; check is the oracle). An edit to the project
# file, nika.yaml, gets the project's two judges: `nika check` on the file
# (its keys and required values and, from the 0.123 line, every beat's
# laws), and `nika arm`, which reads every beat's readiness (cadence, zone,
# suspension, workflow) and is read-only: it schedules nothing and writes
# nothing.
#
# ONE script, TWO dialects, THREE surfaces (Codex emits the Claude Code
# dialect verbatim — live-proven 2026-07-12). Sniffed from stdin — `hook_event_name` is
# Claude Code's, absent from Cursor's):
#   Cursor (afterFileEdit): file_path at the payload root; findings go
#     to STDERR (the hook log) and stdout stays `{}` — never a veto.
#   Claude Code (PostToolUse · matcher Edit|Write|MultiEdit): file_path
#     at tool_input.file_path; findings go to STDERR + exit 2 — the
#     documented feedback channel (the tool already ran, so exit 2 is
#     non-blocking here: Claude SEES the findings and repairs).
#
# Capability-honest: no nika binary means no verdict, never a failure.

# >>> nika-clean-path: every kit hook and helper opens with this same block,
# before it starts any other program (a test keeps the copies identical).
# Hosts start hooks in the open project, and the PATH can name folders the
# repository holds: a relative entry (".", "bin", "node_modules/.bin", the
# empty one) resolves there, and an absolute one can lead there too. Only
# the absolute entries whose real folder (cd -P) lies outside the project
# are kept, as those real folders. The project is each of
# CLAUDE_PROJECT_DIR, CURSOR_PROJECT_DIR and the working folder, with the
# git work tree around each (the nearest folder above holding .git), but
# never the home or a folder above it. A function of builtins, run once in
# a subshell (bash 3.2 cannot parse a case inside $(...)): nothing runs
# before the PATH is set. The kit's manifests start this script with
# /bin/bash -p (see the README for what that does and does not cover).
nika_clean_path() {
  local here dir top root home kept rest
  here="${PWD:-}"
  set --
  home=/
  case "${HOME:-}" in
    /*) cd -P -- "$HOME" 2>/dev/null && home="$PWD" ;;
  esac
  for dir in "${CLAUDE_PROJECT_DIR:-}" "${CURSOR_PROJECT_DIR:-}" "$here"; do
    case "$dir" in
      /*) cd -P -- "$dir" 2>/dev/null || continue ;;
      *) continue ;;
    esac
    top="$PWD"
    while [ -n "$top" ] && [ ! -e "$top/.git" ]; do
      top="${top%/*}"
    done
    for root in "$PWD" "$top"; do
      case "$root" in
        '' | /) continue ;;
      esac
      case "$home/" in
        "$root"/*) continue ;;
      esac
      set -- "$@" "$root"
    done
  done
  kept=""
  rest="${PATH:-}"
  while [ -n "$rest" ]; do
    dir="${rest%%:*}"
    case "$rest" in
      *:*) rest="${rest#*:}" ;;
      *) rest="" ;;
    esac
    case "$dir" in
      /*) cd -P -- "$dir" 2>/dev/null || continue ;;
      *) continue ;;
    esac
    for root; do
      case "$PWD/" in
        "$root"/*) continue 2 ;;
      esac
    done
    kept="${kept:+$kept:}$PWD"
  done
  printf '%s' "$kept"
}
nika_path="$(nika_clean_path)"
unset -f nika_clean_path
PATH="${nika_path:-/usr/bin:/bin}"
export PATH
unset nika_path
# nika_on_path: the nika this PATH names, as an absolute path, when there is
# one. `type -P` searches the PATH alone: a function or an alias named nika
# never answers.
# shellcheck disable=SC2329 # not every script asks for nika
nika_on_path() {
  local bin
  bin="$(type -P nika)" || return 1
  case "$bin" in
    /*) printf '%s\n' "$bin" ;;
    *) return 1 ;;
  esac
}
# <<< nika-clean-path

set -euo pipefail

input="$(cat)"

cc=""
case "$input" in *hook_event_name*) cc=1 ;; esac

done_quiet() {
  printf '{}\n'
  exit 0
}

# file_path from the stdin JSON — python3 when present, sed fallback
# (both dialects carry exactly one "file_path" key, so the flat
# fallback matches either nesting).
if command -v python3 >/dev/null 2>&1; then
  file="$(printf '%s' "$input" | python3 -I -c 'import json,sys
try:
    d = json.load(sys.stdin)
    print(d.get("file_path") or d.get("tool_input", {}).get("file_path", ""))
except Exception:
    print("")' 2>/dev/null || true)"
else
  file="$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
fi

kind=""
case "$file" in
  *.nika) kind=workflow ;;
  nika.yaml | */nika.yaml) kind=project ;;
  *) done_quiet ;;
esac

# The oracle order. NIKA_BIN wins when set: the seatbelt judges with the
# binary the WORK targets, not only whatever the PATH serves. Proven need
# 2026-07-27: the E-split window, where every ratified-grammar file on this
# machine drew a cry from the PATH's 0.105 while engine main already spoke
# the new forms.
#
# A project never chooses the judge. This hook runs on its own after every
# edit, in any repository the editor opens, so nothing the repository holds
# is ever run: a build under the tree's own `target/` is not picked, engine
# tree included. Inside the engine tree (the tree holds `crates/nika-cli`),
# a session that points CARGO_TARGET_DIR at an absolute folder outside the
# tree (one build folder per lane) is judged by that folder's build: the
# session chose it, the repository did not. Elsewhere that folder may hold
# another project's build and is not looked at. Everything else falls back
# to the PATH's nika; to judge with another build, name it with NIKA_BIN in
# the environment the client gives its hooks. Same capability-honesty: an
# unset or broken NIKA_BIN and a missing binary fall back to silence, never
# to a failure.
#
# Only an absolute NIKA_BIN counts, and the PATH is searched in its absolute
# folders only: a relative one resolves against the edited project.

NIKA=""
case "${NIKA_BIN:-}" in
  "") ;;
  /*) NIKA="$NIKA_BIN" ;;
  *) echo "check-on-edit: NIKA_BIN is not an absolute path, so this hook ignores it" >&2 ;;
esac
# Inside the plugin, every helper asks the one resolver, which sits beside
# this hook and applies the order written above. `nika init` empties this
# one line in the copy it writes into a project: there the folder beside the
# hook belongs to the repository, so a project copy never runs anything from
# it and applies the same order itself.
resolver="../bin/nika-kit"
kit=""
if [ -n "$resolver" ]; then
  kit="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$resolver"
fi
if [ -n "$kit" ] && [ -x "$kit" ]; then
  answer="$(bash -p "$kit" --path "$(dirname -- "$file")" 2>/dev/null || true)"
  case "$answer" in
    /*) NIKA="$answer" ;;
    *) [ -n "$NIKA" ] || NIKA="$(nika_on_path || true)" ;;
  esac
elif [ -z "$NIKA" ]; then
  NIKA="$(nika_on_path || true)"
  case "${CARGO_TARGET_DIR:-}" in
    /*)
      root="$(git -C "$(dirname -- "$file")" rev-parse --show-toplevel 2>/dev/null || true)"
      if [ -n "$root" ] && [ -f "$root/crates/nika-cli/Cargo.toml" ] \
        && [ -f "$CARGO_TARGET_DIR/debug/nika" ] && [ -x "$CARGO_TARGET_DIR/debug/nika" ]; then
        build="$(cd "$CARGO_TARGET_DIR/debug" 2>/dev/null && pwd -P || true)"
        tree="$(cd "$root" 2>/dev/null && pwd -P || true)"
        if [ -n "$build" ] && [ -n "$tree" ]; then
          case "$build/" in
            "$tree"/*) ;;
            *) NIKA="$CARGO_TARGET_DIR/debug/nika" ;;
          esac
        fi
      fi
      ;;
  esac
fi

if [ ! -f "$file" ] || ! command -v "$NIKA" >/dev/null 2>&1; then
  # Missing file or binary: nothing to audit (the skill teaches the
  # install line) — stay silent and let the edit flow.
  done_quiet
fi

# --native-strict, not a bare check. The bare verdict passes a workflow
# whose real work happens inside `exec python3 helper.py` — the shape an
# agent reaches for the moment a builtin refuses it, and the one that
# leaves nothing for the permits boundary to bound. Under the flag that
# hint becomes rc=2 and lands here, at the edit, where the reflex forms.
# Measured before wiring: a script wrapper fails, `exec git` passes with
# or without a ledger entry. The flag costs legitimate execs nothing.
set +e
if [ "$kind" = project ]; then
  # Readiness is `nika arm`'s. A beat with a blocker (its workflow
  # unreadable, a required input with no value, a policy the firer
  # refuses) exits 0 from `nika arm` and is a finding here. A beat whose
  # only open question is an unknown (a nested workflow's routes, judged at
  # its own dispatch) is not a defect and stays silent: current engines
  # read it READY, earlier ones UNREADY with no blocker. Without python3 to
  # read the JSON, every UNREADY beat is reported. `nika arm` discovers nika.yaml
  # from its working directory, so it runs from the edited file's own
  # directory.
  project_dir="$(cd -- "$(dirname -- "$file")" && pwd)"
  shape="$("$NIKA" check --color never -- "$file" 2>&1)"
  shape_rc=$?
  beats="$(cd "$project_dir" && "$NIKA" arm --color never 2>&1)"
  beats_rc=$?
  blocked=""
  if command -v python3 >/dev/null 2>&1; then
    blocked="$(cd "$project_dir" && "$NIKA" arm --json 2>/dev/null | python3 -I -c 'import json, sys
try:
    rows = json.load(sys.stdin).get("schedules") or []
except Exception:
    rows = []
print("blocked" if any(row.get("blockers") for row in rows) else "")' 2>/dev/null || true)"
  elif printf '%s' "$beats" | grep -q '\[UNREADY\]'; then
    blocked="blocked"
  fi
  rc=0
  findings=""
  if [ "$shape_rc" -eq 2 ]; then
    rc=2
    findings="$shape"
  fi
  if [ "$beats_rc" -eq 2 ] || [ -n "$blocked" ]; then
    rc=2
    findings="${findings:+$findings
}$beats"
  fi
else
  findings="$("$NIKA" check --native-strict --color never -- "$file" 2>&1)"
  rc=$?
fi
set -e

# WHICH oracle answered. A verdict that does not name the binary behind it
# claims more than it covers — the same law this hook exists to enforce on
# workflows, applied to the hook.
#
# Not hypothetical. Measured 2026-07-28, mid-session: `NIKA_BIN` unset
# resolves to the PATH's brew build, which was one release behind the tree
# and still deferred `${{ const.x }}` paths to run time. On the same file:
#
#   brew 0.106.1  ✔ PERMITS  body fits the declared boundary
#   engine main   ✖ NIKA-SEC-004 ./secret/keys.txt is outside permits.fs.read
#
# The hook fires on its own after every edit, so an agent working ON the
# engine was handed a green from the release it was in the middle of
# fixing — and had no way to see which binary said it. Printing the
# resolved path and version costs one line and makes the divergence
# self-evident the moment it exists.
oracle="$(command -v "$NIKA" 2>/dev/null || printf '%s' "$NIKA")"
# The PATH is the identity. The version string is a TAG, and a tag does not
# order builds by what they contain: measured 2026-07-29, this tree's
# target/debug/nika reports 0.106.0 and carries the fs-permit FIX, while
# the PATH's brew build reports 0.106.1 and carries the FAIL-OPEN. A debug
# build's version tracks the last tag, not the tree, so the higher patch
# number was the vulnerable one. Printing the version first inverted the
# safety ordering for a reader — that was this hook's own repair, one
# iteration ago, and an agent sent to audit something else caught it.
tag="$("$NIKA" --version 2>/dev/null | head -1)"

if [ "$rc" -eq 0 ] && [ -n "${NIKA_CHECK_ANNOUNCE_CLEAN:-}" ]; then
  if [ "$kind" = project ]; then
    printf 'nika check + nika arm · clean · %s (tag %s)\n' "$oracle" "${tag:-unknown}" >&2
  else
    printf 'nika check --native-strict · clean · %s (tag %s)\n' "$oracle" "${tag:-unknown}" >&2
  fi
fi

if [ "$rc" -ne 2 ]; then
  # Clean (0) or broken oracle (3): nothing to teach — silence.
  done_quiet
fi

printf '%s\n' "$findings" | head -c 2000 >&2
# Name the FLAG, not just the verb. A reader told to "re-run nika check"
# runs the bare form, reads a green that this hook does not accept, and
# loops against a gate it cannot see.
#
# Every path inside the command is shell-quoted (%q): a folder or file name
# comes from the project, and the reader is told to run the line.
if [ "$kind" = project ]; then
  printf '\nre-check with the same oracle this hook used (activate a beat only once it reads READY):\n  cd %q && %q check nika.yaml && %q arm --json\n' \
    "$project_dir" "$oracle" "$oracle" >&2
  printf 'the beat, its zone and its activation: https://docs.nika.sh/reference/arm\n' >&2
else
  printf '\nre-check with the same oracle this hook used:\n  %q check --native-strict %q\n' "$oracle" "$file" >&2
fi
printf 'oracle: %s (tag %s · a tag does not say what the build contains)\n' \
  "$oracle" "${tag:-unknown}" >&2
printf 'the judge: NIKA_BIN when set to an absolute path, else inside the engine tree the session build under CARGO_TARGET_DIR (an absolute folder outside the tree), else the first nika in an absolute PATH folder; a build inside a project is never picked. To name another, set NIKA_BIN=<absolute-path-to-nika> where the client starts its hooks\n' >&2
if [ -n "$cc" ]; then
  # PostToolUse exit 2 = stderr fed to Claude, edit already applied.
  exit 2
fi
printf '{}\n'
exit 0
