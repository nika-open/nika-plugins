#!/usr/bin/env bash
# nika-card.test · the plan and review card, on a stub binary. No model,
# no run.
#
# Laws under test: every line is read off `nika check` and `nika inspect`,
# never off the YAML · a host, a write outside the project and a program
# are named as effects · a review is asked for above eight tasks or when an
# effect leaves the machine · an unpriced model is never called free · a
# model a task pins is named as called even on a mock run, the workflow's
# own model, which the mock replaces, is not · the exit code tells a clean check (0) from a refused one (2), no card (3) and
# no binary (127).
#
# Usage: nika-card.test.sh  (exit 0 = all green)
set -uo pipefail

command -v python3 >/dev/null 2>&1 || {
  echo "FAIL nika-card.test: python3 is absent, so nothing was asserted" >&2
  exit 1
}
CARD="$(cd "$(dirname "$0")/.." && pwd)/nika-card.py"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export HOME="$ROOT/home"
mkdir -p "$HOME"
FAILS=0
check() { # check <label> <haystack> <needle>
  if printf '%s' "$2" | grep -qF -- "$3"; then echo "ok   $1"; else
    echo "FAIL $1 — missing: $3"
    FAILS=$((FAILS + 1))
  fi
}
rc_is() { # rc_is <label> <want> <got>
  if [ "$2" -eq "$3" ]; then echo "ok   $1"; else
    echo "FAIL $1 — exit $3, wanted $2"
    FAILS=$((FAILS + 1))
  fi
}

mkdir -p "$ROOT/bin"
# The stub answers from the file's NAME: the YAML itself is never a source.
cat >"$ROOT/bin/nika" <<'STUB'
#!/usr/bin/env bash
file="$2"
case "$1 $(basename "$file" .nika)" in
  "check small")
    case " $* " in
      *" --json "*) echo '{"clean":true,"native_strict_clean":true,"paid_ready":true,"findings":[],"hints":[],"verdicts":{"blockers":[]},"permits":{"needed":{"exec":false,"fs":{"read":["./in/a.json"],"write":[]},"net":{"http":[]},"tools":["nika:read"]}},"cost":{"bounded_total_usd":0,"tasks":[]},"data_journey":{"sources":[{"kind":"fs.read","target":"./in/a.json"}],"writes":[],"model_endpoints":[]}}' ;;
      *) printf '%s\n' "  COST   no model call" ;;
    esac
    ;;
  "inspect small") echo '{"workflow":"small","nodes":[{"id":"a","kind":"task","tool":"nika:read"},{"id":"b","kind":"task","tool":"nika:jq"}],"edges":[{"from":"a","to":"b","kind":"data"}]}' ;;
  "check wide")
    case " $* " in
      *" --model mock/echo "*)
        echo '{"clean":false,"data_journey":{"model_endpoints":[{"model":"mock/echo","task":"draft","provider":"mock","priced":false},{"model":"home/tiny","task":"label","priced":false}]}}'
        exit 2
        ;;
      *" --json "*)
        echo '{"clean":false,"native_strict_clean":false,"paid_ready":false,"findings":[{"code":"NIKA-SEC-009","message":"private data, outside content and a way out"}],"hints":[{"kind":"unbounded_output","task":"draft"}],"verdicts":{"blockers":[]},"permits":{"needed":{"exec":["git"],"fs":{"read":["./state/seen.json"],"write":["./state/seen.json","/tmp/elsewhere.txt"]},"net":{"http":["api.example.com"]},"tools":["nika:fetch","nika:notify","mcp:tracker/create"]}},"cost":{"bounded_total_usd":0.42,"tasks":[{"task":"draft","unbounded_reason":"no max_tokens"}]},"data_journey":{"sources":[{"kind":"fs.read","target":"./state/seen.json"}],"writes":["./state/seen.json"],"model_endpoints":[{"model":"acme/large","task":"draft","priced":true},{"model":"home/tiny","task":"label","priced":false}]}}'
        exit 2
        ;;
      *) printf '%s\n' "  COST   ≤ \$0.42 bounded · 1 task without a ceiling" ;;
    esac
    ;;
  "inspect wide") echo '{"workflow":"wide","nodes":[{"id":"t1","kind":"task","tool":"nika:fetch"},{"id":"t2","kind":"task","tool":"nika:jq","when":"x"},{"id":"t3","kind":"task","fan_out":true},{"id":"t4","kind":"task","tool":"nika:prompt"},{"id":"t5","kind":"task"},{"id":"t6","kind":"task"},{"id":"t7","kind":"task"},{"id":"t8","kind":"task"},{"id":"t9","kind":"task","tool":"nika:write"}],"edges":[{"from":"t1","to":"t9","kind":"data"},{"from":"t2","to":"t9","kind":"data"},{"from":"t1","to":"t5","kind":"control","predicate":"failure"}]}' ;;
  "check mute") echo "this is not json" ;;
  *) exit 64 ;;
esac
STUB
chmod +x "$ROOT/bin/nika"
: >"$ROOT/small.nika"
: >"$ROOT/wide.nika"
: >"$ROOT/mute.nika"
card() { env -u CARGO_TARGET_DIR NIKA_BIN="$ROOT/bin/nika" python3 "$CARD" "$@" 2>&1; }

out="$(card "$ROOT/small.nika")"
rc_is "a clean check is exit 0" 0 $?
check "a job that only reads is said to" "$out" "reads only            yes"
check "the depth counts come from inspect" "$out" "tasks 2 · builtins 2"
check "no gate is said in plain words" "$out" "none: a run never waits for a person"
check "the cost line is the one check prints" "$out" "COST   no model call"
check "a small local job leaves the review optional" "$out" "Review    optional"
check "a job with no model says no model is called on mock" "$out" "called even on mock   no"

out="$(card "$ROOT/wide.nika")"
rc_is "a refused check is exit 2" 2 $?
check "the refusal is named with its code" "$out" "NIKA-SEC-009"
check "a host leaves the machine" "$out" "host api.example.com"
check "the card does not guess what a call to a host does" "$out" "not whether a call there reads or sends"
check "a write outside the project leaves the machine" "$out" "write outside the project /tmp/elsewhere.txt"
check "a notification and an MCP tool leave the machine" "$out" "tool nika:notify, tool mcp:tracker/create"
check "a priced model is spend" "$out" "acme/large (draft)"
check "an unpriced model is never called free" "$out" "unpriced, never free  home/tiny (label)"
check "a model a task pins is called even on a mock run" "$out" "called even on mock   home/tiny (label)"
check "and the card says what that means for a rehearsal" "$out" "never rehearse it on the mock model"
if printf '%s' "$out" | grep -F "called even on mock" | grep -qF "acme/large"; then
  echo "FAIL the workflow's own model, which the mock replaces, is listed as called on mock"
  FAILS=$((FAILS + 1))
else echo "ok   the workflow's own model, which the mock replaces, is not listed"; fi
check "a program is named" "$out" "runs programs         git"
check "a path both read and written is state between runs" "$out" "./state/seen.json"
check "branches, failure routes, joins, fan-outs and gates are counted" "$out" "when: 1 · failure routes 1 · joins 1 · fan-outs 1 · gates 1"
check "a task without a ceiling is named" "$out" "draft (no max_tokens)"
check "nine tasks and an effect that leaves ask for a review" "$out" "Review    needed: 9 tasks, an effect leaves the machine, it runs a program"
data="$(card "$ROOT/wide.nika" --json)"
if printf '%s' "$data" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d["depth"]["tasks"] == 9 and d["review"] and not d["verdict"]["clean"] else 1)'; then
  echo "ok   --json carries the same card as data"
else
  echo "FAIL --json is not the expected shape"
  FAILS=$((FAILS + 1))
fi

# ── the plan the person approved, and what was added since
export CLAUDE_PLUGIN_DATA="$ROOT/data"
mkdir -p "$ROOT/data"
out="$(card "$ROOT/small.nika" --since-plan)"
rc_is "with no remembered plan the exit code is the check's" 0 $?
check "and it is said" "$out" "no plan was remembered for this file"
card "$ROOT/small.nika" --plan >/dev/null
out="$(card "$ROOT/small.nika" --since-plan)"
rc_is "a file that kept to its plan is exit 0" 0 $?
check "and it is said" "$out" "no effect was added"
if ls "$ROOT"/*.json >/dev/null 2>&1; then
  echo "FAIL the remembered plan was written beside the workflow"
  FAILS=$((FAILS + 1))
else echo "ok   the remembered plan stays out of the project"; fi
sed -i.bak 's|"net":{"http":\[\]}|"net":{"http":["new.example.org"]}|' "$ROOT/bin/nika"
out="$(card "$ROOT/small.nika" --since-plan)"
rc_is "an effect added since the plan is exit 4" 4 $?
check "and the added effect is named" "$out" "leaves the machine: host new.example.org"
# Recording the plan again replaces it. That cannot be prevented from here,
# so it is made visible: the card names what the earlier plan did not have.
out="$(card "$ROOT/small.nika" --plan)"
check "a plan recorded again says it replaced the earlier one" "$out" "REPLACED the plan remembered for this file"
check "and names the effect the earlier plan did not have" "$out" "leaves the machine: host new.example.org"
out="$(card "$ROOT/small.nika" --plan)"
check "the same plan recorded twice adds nothing" "$out" "no effect was added"
mv "$ROOT/bin/nika.bak" "$ROOT/bin/nika"

out="$(card "$ROOT/mute.nika")"
rc_is "output that is not JSON is exit 3" 3 $?
check "and it is said plainly" "$out" "No card: nika check printed no JSON"
out="$(card "$ROOT/absent.nika")"
rc_is "a file that is not there is exit 3" 3 $?
out="$(NIKA_BIN="$ROOT/bin/absent" PATH="/usr/bin:/bin" python3 "$CARD" "$ROOT/small.nika" 2>&1)"
rc_is "a missing binary is exit 127" 127 $?
check "and it is said plainly" "$out" "nika is not installed"

if [ "$FAILS" -eq 0 ]; then echo "all green"; else
  echo "$FAILS failure(s)"
  exit 1
fi
