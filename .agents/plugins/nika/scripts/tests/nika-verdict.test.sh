#!/usr/bin/env bash
# nika-verdict.test · the plain verdict, on a stub binary.
#
# Laws under test: the exit code is the check's · a refusal names its
# reason · a check that could not run is neither « ready » nor « not
# ready » · a binary that does not answer is given a time limit, and that
# is said, exit 124.
#
# Usage: nika-verdict.test.sh  (exit 0 = all green)
set -uo pipefail

command -v python3 >/dev/null 2>&1 || {
  echo "FAIL nika-verdict.test: python3 is absent, so nothing was asserted" >&2
  exit 1
}
VERDICT="$(cd "$(dirname "$0")/.." && pwd)/nika-verdict.py"
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

cat >"$ROOT/bin/nika" <<'STUB'
#!/usr/bin/env bash
[ "$1" = check ] || exit 64
case "$2" in
  *slow*) exec sleep 6 ;;
  *crash*)
    echo "the oracle could not read its own tables" >&2
    exit 3
    ;;
  *bad*)
    echo '{"clean":false,"findings":[{"code":"NIKA-AUTH-006","message":"this write has no grant — add it"}],"permits":{"needed":{"fs":{"read":["notes/week.md"]},"net":{"http":["example.org"]},"tools":["nika:read"]}}}'
    exit 2
    ;;
  *) echo '{"clean":true,"findings":[],"permits":{"needed":{"fs":{"read":["notes/week.md"]},"tools":["nika:read"]}}}' ;;
esac
STUB
chmod +x "$ROOT/bin/nika"
for name in good bad crash slow; do printf 'nika: %s\ntasks: {}\n' "$name" >"$ROOT/$name.nika"; done
verdict() { (cd "$ROOT" && env -u CARGO_TARGET_DIR NIKA_BIN="$ROOT/bin/nika" NIKA_KIT_TIMEOUT_SECONDS=1 python3 "$VERDICT" "$@" 2>&1); }

out="$(verdict good.nika)"
rc_is "a clean check is exit 0" 0 $?
check "what the file reads is named" "$out" "Reads: notes/week.md"
check "and it is ready" "$out" "Verdict: ready to run"

out="$(verdict bad.nika)"
rc_is "a refusal is exit 2" 2 $?
check "the host it can reach is named" "$out" "Can reach: example.org"
check "the reason is given in plain words, with its code" "$out" "this write has no grant (ref NIKA-AUTH-006)"

out="$(verdict crash.nika)"
rc_is "a check that could not run keeps its own exit code" 3 $?
check "and says it could not read the file" "$out" "The check could not read this file"
refuse "it is not called ready" "$out" "Verdict: ready"
refuse "nor refused" "$out" "Verdict: not ready"

SECONDS=0
out="$(verdict slow.nika)"
rc_is "a binary that does not answer is exit 124" 124 $?
check "and that is said" "$out" "did not answer within 1 s"
if [ "$SECONDS" -le 4 ]; then echo "ok   the wait is bounded"; else
  echo "FAIL the verdict waited $SECONDS s for the binary"
  FAILS=$((FAILS + 1))
fi

if [ "$FAILS" -eq 0 ]; then echo "all green"; else
  echo "$FAILS failure(s)"
  exit 1
fi
