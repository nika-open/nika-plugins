#!/usr/bin/env bash
# A broken judge must not turn permission-looking stdout into an allow.
# Exercise the installed shim, not a copy of its dispatch, in both dialects.
# A deny is blocked by the hook's own exit 2, with the verdict and a fixed
# line on stderr, the block Claude Code and Codex document with its reason
# and the one all three hosts read alike: a host reads only its own
# dialect's JSON (Claude Code finds no decision in Cursor's
# {"permission":"deny"} and runs the command). Under Cursor (CURSOR_VERSION
# set), which documents no message from exit 2 and hands the agent the
# agent_message of its own deny answer, Cursor's own deny (one flat object)
# is passed on with exit 0; any other deny there is still blocked by exit 2.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHIM="$HERE/../guard-run.sh"
judge_root="$(mktemp -d)"
cleanup() {
  rm -f "$judge_root/nika" "$judge_root/err"
  rmdir "$judge_root"
}
trap cleanup EXIT
# The stub writes its answer and the end of line nika guard writes after
# one, unless GUARD_TEST_CUT is set: then the line stops short, the way a
# judge that dies while writing leaves it.
cat >"$judge_root/nika" <<'EOF'
#!/bin/sh
/bin/cat >/dev/null
if [ -n "$GUARD_TEST_OUTPUT" ]; then
  if [ -n "${GUARD_TEST_CUT:-}" ]; then
    printf '%s' "$GUARD_TEST_OUTPUT"
  else
    printf '%s\n' "$GUARD_TEST_OUTPUT"
  fi
fi
exit "$GUARD_TEST_EXIT"
EOF
chmod +x "$judge_root/nika"
fails=0
checks=0

# The fixed line a deny ends with on stderr.
denied_line='guard_denied: nika guard denied this nika run; the verdict above says why. Repair what it names, then retry.'

# judge <dialect> <exit> <payload> <answer> <expected> [cut]: the shim's
# outcome when the stub answers <answer>, its line cut short when the
# sixth argument is given. <expected> is `unavailable` (a refusal),
# `denied` (the deny blocked by exit 2), or the verdict passed on. The
# hook runs under Cursor when cursor_version is set, and only then.
cursor_version=''
judge() {
  local dialect="$1" code="$2" payload="$3" supplied="$4" expected="$5" cut="${6:-}" out err rc=0
  checks=$((checks + 1))
  [ -z "$cursor_version" ] || dialect="$dialect under Cursor"
  out="$(printf '%s' "$payload" | env -i PATH="$judge_root:/usr/bin:/bin" \
    ${cursor_version:+"CURSOR_VERSION=$cursor_version"} \
    HOME="$judge_root/home" XDG_STATE_HOME="$judge_root/state" GUARD_TEST_CUT="$cut" \
    GUARD_TEST_OUTPUT="$supplied" GUARD_TEST_EXIT="$code" /bin/bash "$SHIM" 2>"$judge_root/err")" || rc=$?
  err="$(cat "$judge_root/err")"
  if [ "$expected" = unavailable ]; then
    # Each refusal names its real cause. The binary is on PATH in every
    # case here, so none of them may send the person to restore it.
    cause='did not give a verdict'
    [ "$code" -ne 3 ] || [ -z "$supplied" ] || cause='could not judge this command'
    if [ "$rc" -eq 2 ] && [ -z "$out" ] && [[ "$err" == *guard_unavailable* ]] \
      && [[ "$err" == *"$cause"* ]] && [[ "$err" != *"not on PATH"* ]]; then
      printf 'ok    %s exit %s refuses (%s)\n' "$dialect" "$code" "$cause"
      return
    fi
  elif [ "$expected" = denied ]; then
    if [ "$rc" -eq 2 ] && [ -z "$out" ] && [ "$err" = "$supplied
$denied_line" ]; then
      printf 'ok    %s exit %s deny blocks by exit 2 (%s)\n' "$dialect" "$code" "${supplied:0:24}"
      return
    fi
  elif [ "$rc" -eq 0 ] && [ "$out" = "$expected" ] && [ -z "$err" ]; then
    printf 'ok    %s exit %s preserves verdict\n' "$dialect" "$code"
    return
  fi
  printf 'FAIL  %s exit %s: expected %s, got rc=%s stdout=%s stderr=%s\n' \
    "$dialect" "$code" "$expected" "$rc" "$out" "$err" >&2
  fails=$((fails + 1))
}

# Both hosts' deny shapes: Cursor's, and Claude Code's (Codex reads the
# same hookSpecificOutput).
cursor_deny='{"permission":"deny","agent_message":"fixture judge refused","user_message":"refused"}'
claude_deny='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"fixture judge refused"}}'

for dialect in cursor claude; do
  if [ "$dialect" = cursor ]; then
    payload='{"command":"nika run fixture.nika","cwd":"/tmp"}'
    unrelated='{"command":"ls","cwd":"/tmp"}'
    allow='{"permission":"allow"}'
    deny='{"permission":"deny","agent_message":"fixture judge refused"}'
  else
    payload='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"nika run fixture.nika"},"cwd":"/tmp"}'
    unrelated='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"/tmp"}'
    allow='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    deny='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"fixture judge refused"}}'
  fi
  judge "$dialect" 0 "$payload" "$allow" "$allow"
  judge "$dialect" 2 "$payload" "$deny" denied
  # A deny in either dialect, on either payload, is blocked by the exit
  # alone, so a host never has to read a dialect that is not its own.
  for answer in "$cursor_deny" "$claude_deny"; do
    for code in 0 2; do
      judge "$dialect" "$code" "$payload" "$answer" denied
    done
  done
  judge "$dialect" 3 "$payload" "$deny" unavailable
  for code in 1 4 127 255; do
    judge "$dialect" "$code" "$payload" "$allow" unavailable
  done
  for code in 0 2 3; do
    judge "$dialect" "$code" "$payload" '' unavailable
  done
  judge "$dialect" 0 "$unrelated" '{}' '{}'
  judge "$dialect" 1 "$unrelated" "$allow" unavailable
  # A verdict is one whole line. Cut short, with a second line, or as a
  # piece of an object (here a deny whose outer brace never came), the
  # answer is no verdict, whatever the exit; a deny on exit 0 still blocks.
  for code in 0 2; do
    judge "$dialect" "$code" "$payload" "$allow" unavailable cut
    judge "$dialect" "$code" "$payload" "$deny" unavailable cut
    judge "$dialect" "$code" "$payload" "${deny%\}}" unavailable
    judge "$dialect" "$code" "$payload" "$deny$deny" unavailable
    judge "$dialect" "$code" "$payload" "$allow
$deny" unavailable
  done
  judge "$dialect" 0 "$payload" '{}' unavailable cut
  judge "$dialect" 0 "$payload" "$deny" denied
  # On exit 2 the judge denied: an answer that does not deny is refused.
  judge "$dialect" 2 "$payload" '{}' unavailable
  judge "$dialect" 2 "$payload" "$allow" unavailable
  judge "$dialect" 2 "$payload" '{"reason":"\"permission\":\"deny\""}' unavailable
  # Encode the payload through a real JSON writer; never execute the command.
  for command in "n'ik'a run x.yaml" 'n\ika run x.yaml' 'echo hook_event_name; ls'; do
    opaque="$(jq -nc --arg dialect "$dialect" --arg command "$command" '
      if $dialect == "cursor" then {command:$command,cwd:"/tmp"}
      else {hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$command},cwd:"/tmp"} end')"
    judge "$dialect" 1 "$opaque" "$allow" unavailable
  done
done

# Under Cursor, on either payload: Cursor's own deny, exactly as nika guard
# writes it (in any key order, its messages holding escapes), is the
# answer, with exit 0, whatever exit the judge gave. Any other deny is
# still blocked by exit 2: one in Claude Code's dialect, one that is not a
# flat object, one with "permission" twice (a parser keeping the last key
# reads the second), a message key twice, a key written with an escape, or
# a key nika guard never writes. A word that held an escape is never
# "deny", so on the judge's exit 2 such an answer denies nothing and is
# refused. An allow is passed on, and a deny cut short is no verdict.
engine_deny='{"agent_message":"say \"x\"\nthen re-check","permission":"deny","user_message":"blocked — repair it"}'
cursor_version=2.1.0
for payload in '{"command":"nika run fixture.nika","cwd":"/tmp"}' \
  '{"hook_event_name":"beforeShellExecution","command":"nika run fixture.nika","cwd":"/tmp"}'; do
  for code in 0 2; do
    judge cursor "$code" "$payload" "$cursor_deny" "$cursor_deny"
    judge claude "$code" "$payload" "$claude_deny" denied
    judge cursor "$code" "$payload" '{"permission":"deny","extra":{"permission":"allow"}}' denied
    judge cursor "$code" "$payload" '{"outer":{"permission":"deny"}}' denied
    judge cursor "$code" "$payload" "$cursor_deny" unavailable cut
    judge cursor "$code" "$payload" "$engine_deny" "$engine_deny"
    judge cursor "$code" "$payload" '{"permission":"deny","permission":"allow"}' denied
    judge cursor "$code" "$payload" '{"permission":"allow","permission":"deny"}' denied
    judge cursor "$code" "$payload" '{"permission":"deny","agent_message":"a","agent_message":"b"}' denied
    judge cursor "$code" "$payload" '{"permission":"deny","permissio\u006e":"allow"}' denied
    judge cursor "$code" "$payload" '{"permission":"deny","continue":"true"}' denied
  done
  judge cursor 2 "$payload" '{"permission":"de\\ny"}' unavailable
  judge cursor 2 "$payload" '{"permission":"de\u006ey"}' unavailable
  judge claude 2 "$payload" '{"hookSpecificOutput":{"permissionDecision":"de\\ny"}}' unavailable
  judge cursor 0 "$payload" '{"permission":"allow"}' '{"permission":"allow"}'
  judge cursor 0 "$payload" '{}' '{}'
done
cursor_version=''

if [ "$fails" -ne 0 ]; then
  printf 'FAIL  %s of %s judge-exit controls\n' "$fails" "$checks" >&2
  exit 1
fi
printf 'OK  %s judge-exit controls; no workflow or effect was executed\n' "$checks"
