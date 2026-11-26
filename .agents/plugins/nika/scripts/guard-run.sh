#!/usr/bin/env bash
# guard-run is a transport adapter: the engine alone decodes the host
# payload, judges shell commands and renders the two hook dialects.
# Cursor uses {command, cwd}; Claude Code/Codex use
# {hook_event_name, tool_input:{command}, cwd}. A verdict that denies is
# answered the way its host documents a deny whose reason reaches the
# agent: Cursor's own answer passed on under Cursor, the hook's exit 2
# with the verdict on stderr everywhere else (see denied below).
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
#     https://learn.chatgpt.com/docs/hooks
# A hook configured to block on failure (Claude Code onFailure "block",
# Cursor failClosed, Codex opt-in failure blocking) turns the warning
# into a refusal; the kit's own manifests set none of them, and neither
# do the copies `nika init` writes. Blocking on failure would also refuse
# every shell command, in every folder, wherever the hook cannot start (no
# /bin/bash, as on Windows) or cannot run to its end: the rule above.
#
# The warning shows once until nika is found again: a marker under
# ${XDG_STATE_HOME:-~/.local/state}/nika/ is written when warning and
# removed the next time the hook finds the binary. When that folder cannot
# be named (no HOME) or cannot hold the marker, the marker is a folder of
# the user's own under the temporary folder instead.

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

# A signal that would end the hook is caught from here on, before anything
# else runs, and ends it with the blocking exit 2: bash 3.2 runs the EXIT
# trap of a shell an uncaught signal ends with a status of 0, then dies of
# the signal (128 + its number), which every host reads as a non-blocking
# error. These are the signals a host, a timer or a resource limit sends
# to end a process; KILL and STOP cannot be caught.
trap 'exit 2' HUP INT QUIT TERM PIPE ALRM USR1 USR2 XCPU XFSZ VTALRM PROF

set -uo pipefail

restore='Put nika back on the editor PATH (brew install nika-open/tap/nika, other paths: nika.sh) and restart the session.'

# Fixed diagnostics only, never interpolated command or payload bytes.
# All three hosts document exit 2 as blocking: no guessed JSON envelope.
refuse() {
  printf 'guard_unavailable: %s\n' "$1" >&2
  exit 2
}

# The judge's answer, and the warning's marker when the state folder cannot
# hold it, go under TMPDIR when it names an absolute folder, else under
# /tmp: a relative one would put them in the folder the hook runs in, the
# open project (the same test as XDG_STATE_HOME's below).
tmp_root="${TMPDIR:-}"
case "$tmp_root" in
  /*) ;;
  *) tmp_root=/tmp ;;
esac
# The folder named in a refusal, printable characters only and bounded.
tmp_shown="${tmp_root//[^[:print:]]/?}"
tmp_shown="${tmp_shown:0:200}"

state="${XDG_STATE_HOME:-}"
case "$state" in
  /*) ;;
  *) state="${HOME:+$HOME/.local/state}" ;;
esac
warned="${state:+$state/nika/guard-off.warned}"
# The fallback marker is a folder: mkdir never follows a link planted at its
# name, and the marker counts only as a real folder this user owns.
warned_tmp="$tmp_root/nika-guard-off.$UID.warned"
warned_before() {
  { [ -n "$warned" ] && [ -e "$warned" ]; } \
    || { [ -d "$warned_tmp" ] && [ ! -L "$warned_tmp" ] && [ -O "$warned_tmp" ]; }
}

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
  if warned_before; then
    # Already warned: the no-opinion answer the engine gives a command
    # that is not a nika run, in every dialect.
    printf '{}\n'
    exit 0
  fi
  if ! { [ -n "$warned" ] && mkdir -p "${warned%/*}" 2>/dev/null \
    && : >>"$warned" 2>/dev/null; }; then
    mkdir "$warned_tmp" 2>/dev/null
  fi
  printf 'guard_off: the nika binary is not on PATH, so the nika guard is off: shell commands run, and a nika run started meanwhile is not checked before it starts. This folder is not a Nika project (no nika.yaml or .nika/ here or above); inside one, the hook refuses every shell command until nika is back. %s This warning shows once until nika is found again.\n' "$restore" >&2
  exit 1
}

# The judge is the first nika in an absolute PATH folder, and the hook runs
# that exact file: a repository cannot put one in front of it.
if bin="$(nika_on_path)"; then
  # The binary is back: the next time it goes missing, warn again.
  if [ -n "$warned" ] && [ -e "$warned" ]; then
    rm -f "$warned" 2>/dev/null
  fi
  if [ -d "$warned_tmp" ] && [ ! -L "$warned_tmp" ]; then
    rmdir "$warned_tmp" 2>/dev/null
  fi
else
  without_binary
fi

# The judge answered but broke: the binary is present, so the repair is
# the binary itself, never the PATH.
broken() {
  refuse "nika guard failed ($1): the nika binary on PATH did not give a verdict, so the hook refuses every shell command until it does. Check it with nika doctor or reinstall it (brew install nika-open/tap/nika, other paths: nika.sh), then retry."
}

# The judge answers within a deadline, or the command is refused. A host
# that times a hook out lets the action through, so a judge that never
# answers (a workflow path that blocks when read, a hung binary) would
# hand the command over unjudged. Past the deadline the hook ends the judge
# and every process it started (its own process group), then refuses. The
# deadline is fixed here, not read from a variable, which a project's
# settings could raise. Every wiring of this hook gives it a 30 s timeout,
# above the deadline, and a test holds each one there: the Claude Code one
# (the kit's hooks/claude-hooks.json, which the Codex plugin also names,
# and the .claude/settings.json nika init writes) and the Cursor one (the
# kit's hooks/cursor-hooks.json and the .cursor/hooks.json nika init
# writes; Cursor reads `timeout` in seconds). No `timeout` binary (macOS
# ships none) and nothing newer than bash 3.2 (macOS /bin/bash).
deadline=20
# The judge's answer goes to a new folder under tmp_root (above).
scratch="$(mktemp -d "$tmp_root/nika-guard.XXXXXX" 2>/dev/null)" \
  || refuse "the hook could not make a temporary folder for the judge's answer, so it cannot hold nika guard to its deadline: it refuses every shell command until it can. Check that $tmp_shown is writable, then retry."
# However the hook ends, the judge's group and the watcher end with it: a
# host that stops the hook (a signal to its process group) would otherwise
# leave the judge running in the group of its own it was given below.
# From here on every end but the verdict's own exit 0 is the blocking exit
# 2: the trap keeps the status the hook ended with and turns any other one
# into 2 (an unforeseen failure exits 1, which every host reads as a
# non-blocking error). A caught signal ends it with 2 as well (the trap
# set after the PATH block).
judge=""
watch=""
# shellcheck disable=SC2329 # run by the EXIT trap below
finish() {
  st=$?
  [ -z "$judge" ] || kill -KILL -- "-$judge" 2>/dev/null || kill -KILL "$judge" 2>/dev/null
  [ -z "$watch" ] || kill -TERM "$watch" 2>/dev/null
  rm -rf "$scratch"
  [ "$st" -eq 0 ] || exit 2
}
trap finish EXIT

# Stdin goes directly to the engine's bounded reader, never into an
# unbounded shell variable. 0/2 carry a judged verdict; 3 is unavailable.
# Job control gives the judge a process group of its own, so the deadline
# ends everything it started, and `<&0` hands it the hook's stdin (a
# background job otherwise reads /dev/null). bash sets that group from both
# sides of the fork; on macOS the child's call can fail under load while the
# parent's holds, and bash then prints a diagnostic of its own. The hook's
# stderr carries only refusals, so it points at /dev/null for the fork.
exec 3>&2 2>/dev/null
set -m
"$bin" guard --stdin <&0 >"$scratch/verdict" 2>/dev/null 3>&- &
judge=$!
set +m
exec 2>&3 3>&-
(
  nap=""
  trap '[ -z "$nap" ] || kill "$nap" 2>/dev/null; exit 0' TERM
  sleep "$deadline" &
  nap=$!
  wait "$nap"
  : >"$scratch/expired"
  kill -KILL -- "-$judge" 2>/dev/null || kill -KILL "$judge" 2>/dev/null
) >/dev/null 2>&1 &
watch=$!
wait "$judge" 2>/dev/null && rc=0 || rc=$?
kill -TERM "$watch" 2>/dev/null
wait "$watch" 2>/dev/null
watch=""
# Whatever the judge left in its group ends with it.
kill -KILL -- "-$judge" 2>/dev/null || kill -KILL "$judge" 2>/dev/null
judge=""
if [ -e "$scratch/expired" ]; then
  refuse "nika guard did not answer within $deadline s, so the hook refuses this command rather than let it run unjudged. Check what the command names (a workflow path that is not a regular file blocks a reader; a very large workflow can take longer than $deadline s to judge) and the binary with nika doctor, then retry."
fi
case "$rc" in
  0 | 2 | 3) ;;
  *) broken "exit $rc" ;;
esac
# The answer is read only when it is no larger than an answer can be: a
# deny reason is capped at 2000 bytes, and 16 KiB leaves room for the JSON
# escapes around it.
size="$(wc -c <"$scratch/verdict" 2>/dev/null)"
size="${size//[!0-9]/}"
if [ -z "$size" ] || [ "$size" -eq 0 ]; then
  broken "exit $rc, no output"
fi
if [ "$size" -gt 16384 ]; then
  broken "exit $rc, an answer longer than any verdict"
fi
raw="$(
  head -c 16384 "$scratch/verdict"
  printf x
)"
raw="${raw%x}"
nl='
'
out="${raw%"$nl"}"
if [ "$rc" -eq 3 ]; then
  # An unreadable/truncated payload cannot establish the host dialect.
  # Preserve the engine's explanation, but block via the shared protocol.
  # The judge is present and answered: its reason is the cause.
  printf '%s\n' "$out" >&2
  refuse "nika guard could not judge this command (exit 3); the reason above is the cause. The nika binary is on PATH and answered, so restoring it changes nothing: make what the reason names visible on the command line (for example a command or workflow path written out, not held in a variable), then retry."
fi

# A verdict is one line written whole: the JSON object nika guard prints
# and the end of line after it. A host reads the answer as JSON, and one
# that cannot (Claude Code, on exit 0) takes it as plain text and lets the
# command through, so an answer cut short (a judge that died writing it),
# a second line or text around the object is no verdict.
if [ "$out" = "$raw" ]; then
  broken "exit $rc, an answer cut short (its line does not end)"
fi
case "$out" in
  *"$nl"*) broken "exit $rc, an answer of more than one line" ;;
esac
# awk reads the object (POSIX awk; bash 3.2 matches a pattern against a
# long answer far too slowly): every string must close, and every member
# must hold a string or an object, the only values nika guard writes. Each
# escape becomes one "~", so a string that held one is an ordinary string,
# never "deny", "allow" or a key the hook reads. On exit 2 the judge
# denied, so the answer must deny: a member "permission" (Cursor's) or
# "permissionDecision" (Claude Code's and Codex's) whose value is "deny"
# (awk exit 2 when it does not). An answer that denies, on any exit, is
# awk's exit 3, or 4 only when it is exactly Cursor's own deny as nika
# guard writes it: one flat object holding "permission" once, with "deny",
# beside at most one "agent_message" and one "user_message", and no other
# key. When in doubt, a deny is exit 3, which blocks. This is not a JSON
# parser: it checks that shape and nothing more.
# shellcheck disable=SC2016 # an awk program, not shell text
verdict_awk='{
  t = $0
  gsub(/\\./, "~", t)
  shape = ""
  while (match(t, /"[^"]*"/)) {
    between = substr(t, 1, RSTART - 1)
    if (between ~ /[^{}:,]/) exit 1
    word = substr(t, RSTART + 1, RLENGTH - 2)
    if (index(word, "~") > 0) letter = "s"
    else if (word == "deny") letter = "d"
    else if (word == "permission") letter = "c"
    else if (word == "permissionDecision") letter = "p"
    else if (word == "agent_message") letter = "a"
    else if (word == "user_message") letter = "u"
    else letter = "s"
    shape = shape between letter
    t = substr(t, RSTART + RLENGTH)
  }
  if (t ~ /[^{}:,]/) exit 1
  shape = shape t
  folded = shape
  while (gsub(/[{]([spdcau]:[spdcauo](,[spdcau]:[spdcauo])*)?[}]/, "o", folded) > 0) {
  }
  if (folded != "o") exit 1
  denies = shape ~ /[{,][pc]:d[,}]/
  if (code == 2 && !denies) exit 2
  if (!denies) exit 0
  keys = shape
  permissions = gsub(/[{,]c:/, "", keys)
  keys = shape
  agents = gsub(/[{,]a:/, "", keys)
  keys = shape
  users = gsub(/[{,]u:/, "", keys)
  if (shape ~ /^[{][cau]:[spdcau](,[cau]:[spdcau])*[}]$/ && shape ~ /[{,]c:d[,}]/ &&
    permissions == 1 && agents <= 1 && users <= 1) exit 4
  exit 3
}'
# The judge denied. Each host documents its own way to block a command and
# hand the agent the reason (read 2026-11-26):
#   - Claude Code: exit 2 blocks, and "the message that comes with the
#     block is your hook's stderr". https://code.claude.com/docs/en/hooks
#   - Codex: exit 2 with "the blocking reason" on stderr denies the call.
#     https://learn.chatgpt.com/docs/hooks
#   - Cursor: exit 2 blocks ("equivalent to returning permission: deny"),
#     but no message from it is documented; the agent is sent the
#     agent_message of a permission "deny" answer on exit 0.
#     https://cursor.com/docs/hooks
# So under Cursor (which sets CURSOR_VERSION for every hook) Cursor's own
# deny, exactly as nika guard writes it, is passed on as the answer, with
# exit 0. Every other deny blocks by the hook's exit 2, with the verdict on
# stderr ahead of a fixed line: a deny passed on as JSON is read only by
# the host whose dialect it speaks (Claude Code given Cursor's
# {"permission":"deny"} finds no decision in it and runs the command), and
# exit 2 is the block all three read alike. nika guard answers in Cursor's
# dialect only for a payload without hook_event_name, and Cursor's hooks
# documentation lists hook_event_name among the fields every hook receives
# (read 2026-11-26): a current Cursor payload is answered in Claude Code's
# shape, so its deny is blocked by exit 2, and that documentation does not
# say the reason then reaches the agent.
denied() {
  printf '%s\n' "$out" >&2
  printf 'guard_denied: nika guard denied this nika run; the verdict above says why. Repair what it names, then retry.\n' >&2
  exit 2
}
shape_rc=0
printf '%s\n' "$out" | awk -v code="$rc" "$verdict_awk" 2>/dev/null || shape_rc=$?
case "$shape_rc" in
  0) ;;
  1) broken "exit $rc, an answer that is not a verdict" ;;
  2) broken "exit 2, an answer that does not deny" ;;
  3) denied ;;
  4) [ -n "${CURSOR_VERSION:-}" ] || denied ;;
  *) refuse "the hook could not read nika guard's answer (awk exit $shape_rc), so it refuses every shell command until it can: it reads the answer with awk, which the PATH must hold." ;;
esac

# The verdict is the host's answer (an allow, no opinion, or Cursor's own
# deny under Cursor): one that cannot be written is none.
printf '%s\n' "$out" || exit 2
exit 0
