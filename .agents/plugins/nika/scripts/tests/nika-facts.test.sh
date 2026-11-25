#!/usr/bin/env bash
# nika-facts.test · the names a skill injects when it loads, on a stub
# binary. No model, no run.
#
# Laws under test: builtins and model routes are read from the binary, not
# written in the script · the MCP shelf is printed only by a binary that
# lists it · a missing binary, a binary that answers nothing and a missing
# python3 each print one plain line and exit 0, since a skill must still
# load · what it prints stays short enough to inject (at most sixty lines,
# each bounded), whatever the binary answers · a binary that hangs is given
# a time limit, and the skill still loads.
#
# Usage: nika-facts.test.sh  (exit 0 = all green)
set -uo pipefail

FACTS="$(cd "$(dirname "$0")/.." && pwd)/nika-facts.sh"
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

mkdir -p "$ROOT/new" "$ROOT/old" "$ROOT/mute" "$ROOT/proj"
stub() { # stub <dir> <catalog help text>
  cat >"$1/nika" <<STUB
#!/usr/bin/env bash
case "\$*" in
  "--version") echo "nika 9.9.9 (stub)" ;;
  "spec --canon") printf '%s\n' 'verbs:' '  count: 4' 'builtins:' '  count: 2' '  items:' '    - zap' '    - pow' 'providers:' '  items:' '    - not_a_builtin' ;;
  "catalog --json") echo '{"providers":[{"id":"acme","cheap_model":"small-9","default_model":"big-9","resolves":true},{"id":"home","default_model":"tiny","local":true,"resolves":true},{"id":"gone","cheap_model":"x","resolves":false}]}' ;;
  "catalog --help") echo "$2" ;;
  "catalog --mcp") echo "filesystem  read and write files in a folder" ;;
  "trace ls --json") echo '{"traces":[]}' ;;
  *) exit 64 ;;
esac
STUB
  chmod +x "$1/nika"
}
stub "$ROOT/new" "Usage: nika catalog [--tools] [--mcp] [--json]"
stub "$ROOT/old" "Usage: nika catalog [--tools] [--json]"
printf '#!/usr/bin/env bash\nexit 1\n' >"$ROOT/mute/nika"
chmod +x "$ROOT/mute/nika"
facts() { env -u CARGO_TARGET_DIR NIKA_BIN="$1/nika" bash "$FACTS" "$ROOT/proj" 2>&1; }

out="$(facts "$ROOT/new")"
rc_is "the facts are printed" 0 $?
check "the binary and its version are named" "$out" "nika 9.9.9 (stub)"
check "builtins come from the binary" "$out" "builtins: nika:zap, nika:pow"
refuse "a list that is not the builtins is not read as one" "$out" "not_a_builtin"
check "a provider's cheaper model is its route" "$out" "acme/small-9"
check "a local route is marked" "$out" "home/tiny (local)"
refuse "a provider this binary does not resolve is left out" "$out" "gone/x"
check "a binary that lists the MCP shelf has it printed" "$out" "MCP shelf: filesystem"

out="$(facts "$ROOT/old")"
check "a binary without the shelf says so, in neutral words" "$out" "this binary prints no list of it"
refuse "and no shelf is invented" "$out" "filesystem"

out="$(facts "$ROOT/mute")"
rc_is "a binary that answers nothing still lets the skill load" 0 $?
check "and each missing list says where to read it" "$out" "not listed by"

out="$(NIKA_BIN="$ROOT/absent/nika" PATH="/usr/bin:/bin" bash "$FACTS" "$ROOT/proj" 2>&1)"
rc_is "a missing binary still lets the skill load" 0 $?
check "and it is said in one plain line" "$out" "no nika binary was found"

# ── what is injected stays short, whatever the binary answers
mkdir -p "$ROOT/chatty" "$ROOT/slow"
cat >"$ROOT/chatty/nika" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "--version") for n in $(seq 1 200); do echo "nika 9.9.9 line $n"; done ;;
  "spec --canon")
    printf '%s\n' 'builtins:' '  items:'
    for n in $(seq 1 400); do echo "    - builtin_number_$n"; done
    ;;
  "catalog --json")
    printf '{"providers":['
    for n in $(seq 1 400); do printf '{"id":"provider%s","cheap_model":"model-number-%s","resolves":true},' "$n" "$n"; done
    printf '{"id":"last","cheap_model":"m","resolves":true}]}\n'
    ;;
  "catalog --help") echo "Usage: nika catalog [--mcp]" ;;
  "catalog --mcp") for n in $(seq 1 400); do echo "server-$n  does a thing"; done ;;
  *) exit 64 ;;
esac
STUB
printf '#!/usr/bin/env bash\nexec sleep 6\n' >"$ROOT/slow/nika"
chmod +x "$ROOT/chatty/nika" "$ROOT/slow/nika"
out="$(facts "$ROOT/chatty")"
lines="$(printf '%s\n' "$out" | grep -c '')"
if [ "$lines" -le 60 ]; then echo "ok   a chatty binary still gives at most sixty lines ($lines)"; else
  echo "FAIL the facts grew to $lines lines, over the 60 they are allowed"
  FAILS=$((FAILS + 1))
fi
longest="$(printf '%s\n' "$out" | awk '{ if (length($0) > n) n = length($0) } END { print n + 0 }')"
if [ "$longest" -le 1800 ]; then echo "ok   and each line is bounded ($longest characters at most)"; else
  echo "FAIL a line of the facts is $longest characters long"
  FAILS=$((FAILS + 1))
fi

# ── a binary that hangs does not hold the skill
SECONDS=0
out="$(NIKA_KIT_TIMEOUT_SECONDS=1 facts "$ROOT/slow")"
rc_is "a binary that hangs still lets the skill load" 0 $?
if [ "$SECONDS" -le 12 ]; then echo "ok   within the time limit of each call ($SECONDS s)"; else
  echo "FAIL the facts waited $SECONDS s on a binary that hangs"
  FAILS=$((FAILS + 1))
fi
check "and each list it could not read says where to read it" "$out" "not listed by"
check "the count of waiting runs is unknown, not zero" "$out" "runs waiting for an answer in $ROOT/proj: unknown"

if [ "$FAILS" -eq 0 ]; then echo "all green"; else
  echo "$FAILS failure(s)"
  exit 1
fi
