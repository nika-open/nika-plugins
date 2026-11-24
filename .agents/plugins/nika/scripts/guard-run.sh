#!/usr/bin/env bash
# guard-run is a transport adapter: the engine alone decodes the host
# payload, judges shell commands and renders the two hook dialects.
# Cursor uses {command, cwd}; Claude Code/Codex use
# {hook_event_name, tool_input:{command}, cwd}.
#
# Comfort hooks may degrade quietly. This execution guard cannot infer
# NotOurs from raw substrings when its sole judge is unavailable: JSON
# escapes and shell quoting defeat a raw "nika" substring filter, and
# command text can contain a misleading "hook_event_name". So the shim
# never reads the payload. When the nika binary is missing it decides
# from where the HOOK runs instead:
#
#   - Inside a Nika project, it refuses every shell command (exit 2).
#     A project is a directory holding nika.yaml (the file the engine's
#     project discovery walks up for) or a .nika/ store, checked in the
#     host's project directory (CLAUDE_PROJECT_DIR, CURSOR_PROJECT_DIR)
#     and in the hook's own working directory, and in every ancestor of
#     each. ~/.nika is the user-level store, not a project.
#   - Elsewhere, the command goes through, with one warning that the
#     guard is off until nika is back on PATH. Failing closed in every
#     folder punished an install problem with a bricked editor.
#
# Residual, outside a project with nika missing from this PATH: a nika
# run started by an absolute path (or under another PATH) is not judged
# by this hook. A plain `nika run` fails there anyway: nothing to run.
#
# The warning is exit 1 with the text on stderr and nothing on stdout,
# the one channel all three hosts document as non-blocking by default:
#   - Claude Code: any exit other than 0 or 2 with plain or no stdout is
#     a non-blocking error; the action goes ahead and the person sees a
#     "hook error" notice carrying stderr.
#     https://code.claude.com/docs/en/hooks
#   - Cursor: other non-zero exits "fail open by default: Cursor logs the
#     failure and allows the action through". JSON such as systemMessage
#     on exit 0 is not an option: a response that does not match the
#     hook's schema blocks the action.
#     https://cursor.com/docs/hooks
#   - Codex: a failed PreToolUse run is reported and the tool call
#     continues; its source records "hook exited with code 1", without
#     the stderr text.
#     https://developers.openai.com/codex/hooks
# A hook configured to block on failure (Claude Code onFailure "block",
# Cursor failClosed, Codex opt-in failure blocking) turns the warning
# into a refusal; the kit's own manifests set none of them.
#
# The warning shows once until nika is found again: a marker under
# ${XDG_STATE_HOME:-~/.local/state}/nika/ is written when warning and
# removed the next time the hook finds the binary.
set -uo pipefail

restore='Put nika back on the editor PATH (brew install nika-open/tap/nika, other paths: nika.sh) and restart the session.'

# Fixed diagnostics only, never interpolated command or payload bytes.
# All three hosts document exit 2 as blocking: no guessed JSON envelope.
refuse() {
  printf 'guard_unavailable: %s\n' "$1" >&2
  exit 2
}

state="${XDG_STATE_HOME:-}"
case "$state" in
  /*) ;;
  *) state="${HOME:+$HOME/.local/state}" ;;
esac
warned="${state:+$state/nika/guard-off.warned}"

# nika_project <dir>: print the marker that makes <dir> or an ancestor a
# Nika project. Returns 1 when none does, 2 when <dir> does not resolve.
nika_project() {
  local dir
  dir="$(cd "$1" 2>/dev/null && pwd -P)" || return 2
  while :; do
    if [ -e "${dir%/}/nika.yaml" ]; then
      printf '%s\n' "${dir%/}/nika.yaml"
      return 0
    fi
    if [ -d "${dir%/}/.nika" ] && [ "$dir" != "$home" ]; then
      printf '%s\n' "${dir%/}/.nika/"
      return 0
    fi
    [ "$dir" != / ] || return 1
    dir="${dir%/*}"
    [ -n "$dir" ] || dir=/
  done
}

without_binary() {
  local dir root rc located=""
  home=""
  if [ -n "${HOME:-}" ]; then
    home="$(cd "$HOME" 2>/dev/null && pwd -P)"
  fi
  for dir in "${CLAUDE_PROJECT_DIR:-}" "${CURSOR_PROJECT_DIR:-}" "${PWD:-}"; do
    [ -n "$dir" ] || continue
    root="$(nika_project "$dir")" && rc=0 || rc=$?
    case "$rc" in
      0)
        root="${root//[[:cntrl:]]/}"
        refuse "the nika binary is not on PATH, and this is a Nika project ($root): the hook refuses every shell command here until its judge is back. $restore"
        ;;
      1) located=1 ;;
    esac
  done
  if [ -z "$located" ]; then
    refuse "the nika binary is not on PATH, and the hook could not resolve the directory it runs in, so it cannot rule out a Nika project: it refuses every shell command until its judge is back. $restore"
  fi
  if [ -n "$warned" ] && [ -e "$warned" ]; then
    # Already warned: the no-opinion answer the engine gives a command
    # that is not a nika run, in every dialect.
    printf '{}\n'
    exit 0
  fi
  if [ -n "$warned" ]; then
    mkdir -p "${warned%/*}" 2>/dev/null && : >>"$warned" 2>/dev/null
  fi
  printf 'guard_off: the nika binary is not on PATH, so the nika guard is off: shell commands run, and a nika run started meanwhile is not checked before it starts. This folder is not a Nika project (no nika.yaml or .nika/ here or above); inside one, the hook refuses every shell command until nika is back. %s This warning shows once until nika is found again.\n' "$restore" >&2
  exit 1
}

if command -v nika >/dev/null 2>&1; then
  # The binary is back: the next time it goes missing, warn again.
  if [ -n "$warned" ] && [ -e "$warned" ]; then
    rm -f "$warned" 2>/dev/null
  fi
else
  without_binary
fi

# The judge answered but broke: the binary is present, so the repair is
# the binary itself, never the PATH.
broken() {
  refuse "nika guard failed ($1): the nika binary on PATH did not give a verdict, so the hook refuses every shell command until it does. Check it with nika doctor or reinstall it (brew install nika-open/tap/nika, other paths: nika.sh), then retry."
}

# Stdin goes directly to the engine's bounded reader, never into an
# unbounded shell variable. 0/2 carry a judged verdict; 3 is unavailable.
out="$(nika guard --stdin 2>/dev/null)" && rc=0 || rc=$?
case "$rc" in
  0 | 2 | 3) ;;
  *) broken "exit $rc" ;;
esac
if [ -z "$out" ]; then
  broken "exit $rc, no output"
fi
if [ "$rc" -eq 3 ]; then
  # An unreadable/truncated payload cannot establish the host dialect.
  # Preserve the engine's explanation, but block via the shared protocol.
  # The judge is present and answered: its reason is the cause.
  printf '%s\n' "$out" >&2
  refuse "nika guard could not judge this command (exit 3); the reason above is the cause. The nika binary is on PATH and answered, so restoring it changes nothing: make what the reason names visible on the command line (for example a command or workflow path written out, not held in a variable), then retry."
fi

printf '%s\n' "$out"
exit 0
