#!/usr/bin/env bash
# nika-pending.test · the list of runs that wait, on a stub binary.
#
# Laws under test: a trace line that is JSON without being an event never
# hides a run that waits · an answer of another shape from the binary is
# an empty list, not a crash · a binary that does not answer in time is
# said, exit 3, and is not « nothing waits » · the search for the workflow
# file is bounded: no directory link is followed, four levels deep · the
# resume line repeats the model the first run was given on its command
# line, and a model name that is not plain is never printed in it.
#
# Usage: nika-pending.test.sh  (exit 0 = all green)
set -uo pipefail

command -v python3 >/dev/null 2>&1 || {
  echo "FAIL nika-pending.test: python3 is absent, so nothing was asserted" >&2
  exit 1
}
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export HOME="$ROOT/home"
mkdir -p "$HOME" "$ROOT/bin"
FAILS=0
check() { # check <label> <haystack> <needle>
  if printf '%s' "$2" | grep -qF -- "$3"; then echo "ok   $1"; else
    echo "FAIL $1 — missing: $3"
    FAILS=$((FAILS + 1))
  fi
}
refuse() { # refuse <label> <haystack> <needle>
  if printf '%s' "$2" | grep -qF -- "$3"; then
    echo "FAIL $1 — unexpected: $3"
    FAILS=$((FAILS + 1))
  else echo "ok   $1"; fi
}
rc_is() { # rc_is <label> <want> <got>
  if [ "$2" -eq "$3" ]; then echo "ok   $1"; else
    echo "FAIL $1 — exit $3, wanted $2"
    FAILS=$((FAILS + 1))
  fi
}

P="$ROOT/proj"
mkdir -p "$P/.nika/traces" "$P/a/b/c/d" "$P/workflows"
printf '%s\n' \
  '[]' \
  '"a line that is JSON and not an event"' \
  '7' \
  '{"kind":"workflow_started","execution":"not an object","fields":"not a list"}' \
  '{"kind":"workflow_started","execution":{"uuid":"e1"},"fields":[{"key":"inputs","value":"[1, 2]"},{"key":"model_override","value":"mock/echo"}]}' \
  '{"kind":"workflow_paused","fields":[{"key":"message","value":"Send the weekly digest?"}, 5, {"key":["odd"],"value":1}]}' \
  >"$P/.nika/traces/odd.ndjson"
printf '{"kind":"workflow_started","execution":{"uuid":"e2"},"fields":[{"key":"model_override","value":"acme/x; touch pwned"}]}\n{"kind":"workflow_paused","fields":[{"key":"message","value":"Publish the page?"}]}\n' \
  >"$P/.nika/traces/deep.ndjson"
printf 'nika: weekly-digest\ntasks: {}\n' >"$P/workflows/digest.nika"
printf 'nika: too-deep\ntasks: {}\n' >"$P/a/b/c/d/deep.nika"
ln -s . "$P/workflows/loop"
ln -s "$P" "$P/again"

stub() { # stub <name> <body of the answer to `trace ls`>
  # shellcheck disable=SC2016 # the stub's own $1 and $2, written as text
  printf '#!/bin/sh\n[ "$1 $2" = "trace ls" ] || exit 64\n%s\n' "$2" >"$ROOT/bin/$1"
  chmod +x "$ROOT/bin/$1"
}
LISTED='{"traces":[7,"x",{"state":"paused","path":".nika/traces/odd.ndjson","workflow":"weekly-digest","paused_task":"approve"},{"state":"paused","path":".nika/traces/deep.ndjson","workflow":"too-deep","paused_task":"approve"}]}'
stub listed "printf '%s' '$LISTED'"
stub other-shape "printf '%s' '[1, 2, 3]'"
stub slow "sleep 5; printf '%s' '$LISTED'"
pending() { # pending <stub> [args…]
  local bin="$1"
  shift
  env -u CARGO_TARGET_DIR NIKA_BIN="$ROOT/bin/$bin" NIKA_KIT_TIMEOUT_SECONDS=1 python3 "$HERE/nika-pending.py" "$P" "$@" 2>&1
}

out="$(pending listed)"
rc_is "a trace with lines of other shapes still lists its run" 4 $?
check "the run is named with its question" "$out" "weekly-digest is waiting at \`approve\`"
check "its question is shown" "$out" "Send the weekly digest?"
check "the workflow file is found by its name" "$out" "nika run workflows/digest.nika"
check "the model the first run was given is repeated" "$out" "nika run workflows/digest.nika --model mock/echo --resume .nika/traces/odd.ndjson"
check "a file past four levels is not searched for" "$out" "nika run <file.nika> --model <the same model as before> --resume .nika/traces/deep.ndjson"
refuse "a model name that is not plain is never printed" "$out" "touch pwned"
refuse "a directory link is never followed" "$out" "loop/"

out="$(pending other-shape)"
rc_is "an answer of another shape is an empty list" 0 $?
check "and it is said plainly" "$out" "No run is waiting"

SECONDS=0
out="$(pending slow)"
rc_is "a binary that does not answer in time is exit 3" 3 $?
check "and it is not called an empty list" "$out" "could not be listed"
refuse "nor « nothing waits »" "$out" "No run is waiting"
if [ "$SECONDS" -le 4 ]; then echo "ok   the wait is bounded"; else
  echo "FAIL the helper waited $SECONDS s for the binary"
  FAILS=$((FAILS + 1))
fi
out="$(pending slow --json)"
rc_is "the same in JSON" 3 $?
check "with the reason" "$out" '"error"'

if [ "$FAILS" -eq 0 ]; then echo "all green"; else
  echo "$FAILS failure(s)"
  exit 1
fi
