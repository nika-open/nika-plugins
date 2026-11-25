#!/usr/bin/env bash
# check-on-edit-oracle.test.sh: which binary the edit hook judges with.
#
# The order under test: NIKA_BIN when set; else, inside the engine tree,
# the session's CARGO_TARGET_DIR build when that folder is absolute and
# outside the tree; else the PATH's `nika`. A build under a tree's own
# target/ never judges, engine tree included: a project does not choose
# its judge. The session folder never judges a file outside the engine
# tree: there it may hold another project's build.
#
# Stub binaries stand in for the real ones, so this runs with no engine
# build. Each stub refuses every file and names itself in its finding; the
# hook's stderr then says which one answered.
#
# Usage: check-on-edit-oracle.test.sh  (exit 0 = all green)
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$ROOT"' EXIT
export HOME="$ROOT/home"
mkdir -p "$HOME"
fails=0

# stub <dir> <name>: an executable `nika` that refuses every check as <name>
stub() {
  mkdir -p "$1"
  cat >"$1/nika" <<EOF
#!/usr/bin/env bash
case "\$1" in
  --version) echo "nika 0.0.0 ($2)" ;;
  *) echo "finding from $2"; exit 2 ;;
esac
EOF
  chmod +x "$1/nika"
}

stub "$ROOT/explicit" explicit
stub "$ROOT/session-target/debug" session-target
stub "$ROOT/path-bin" path-bin

# The engine tree: a git repository holding crates/nika-cli and a tree build.
ENGINE="$ROOT/engine"
mkdir -p "$ENGINE/crates/nika-cli" "$ENGINE/flows"
: >"$ENGINE/crates/nika-cli/Cargo.toml"
stub "$ENGINE/target/debug" tree-build
git -C "$ENGINE" init -q
printf 'nika: flow\npermits: {}\ntasks: {}\n' >"$ENGINE/flows/flow.nika"

# A project outside the engine: a git repository with no crates/nika-cli.
PROJECT="$ROOT/project"
mkdir -p "$PROJECT"
git -C "$PROJECT" init -q
printf 'nika: flow\npermits: {}\ntasks: {}\n' >"$PROJECT/flow.nika"

# judge <label> <file> <want> [env assignments...]: the hook's oracle line names <want>
judge() {
  local label="$1" file="$2" want="$3"
  shift 3
  local payload out
  payload="$(printf '{"hook_event_name":"PostToolUse","tool_input":{"file_path":"%s"}}' "$file")"
  out="$(printf '%s' "$payload" | env -u NIKA_BIN -u CARGO_TARGET_DIR \
    PATH="$ROOT/path-bin:/usr/bin:/bin" "$@" bash "$HOOK" 2>&1)"
  if printf '%s' "$out" | grep -qF "finding from $want"; then
    printf 'ok   %s\n' "$label"
  else
    printf 'FAIL %s: wanted the %s judge, got:\n%s\n' "$label" "$want" "$out"
    fails=$((fails + 1))
  fi
}

# The same order must hold through the plugin's resolver (bin/nika-kit sits
# beside the hook) and in the lone copy `nika init` writes into a project,
# which has no resolver and applies the order itself.
mkdir -p "$ROOT/lone"
cp "$HERE/../check-on-edit.sh" "$ROOT/lone/check-on-edit.sh"
for HOOK in "$HERE/../check-on-edit.sh" "$ROOT/lone/check-on-edit.sh"; do
  case "$HOOK" in "$ROOT"/*) where="lone copy" ;; *) where="in the plugin" ;; esac
  judge "$where · NIKA_BIN wins everywhere" "$ENGINE/flows/flow.nika" explicit \
    NIKA_BIN="$ROOT/explicit/nika" CARGO_TARGET_DIR="$ROOT/session-target"
  judge "$where · inside the engine, the session target folder judges" "$ENGINE/flows/flow.nika" session-target \
    CARGO_TARGET_DIR="$ROOT/session-target"
  judge "$where · inside the engine, no session folder: the PATH judges, never the tree's own build" "$ENGINE/flows/flow.nika" path-bin
  judge "$where · a session folder with no build falls back to the PATH" "$ENGINE/flows/flow.nika" path-bin \
    CARGO_TARGET_DIR="$ROOT/empty-target"
  judge "$where · a session folder inside the repository never judges" "$ENGINE/flows/flow.nika" path-bin \
    CARGO_TARGET_DIR="$ENGINE/target"
  judge "$where · a relative session folder never judges" "$ENGINE/flows/flow.nika" path-bin \
    CARGO_TARGET_DIR="target"
  judge "$where · outside the engine, the session folder never judges" "$PROJECT/flow.nika" path-bin \
    CARGO_TARGET_DIR="$ROOT/session-target"
  judge "$where · outside the engine, NIKA_BIN names the judge" "$PROJECT/flow.nika" explicit \
    NIKA_BIN="$ROOT/explicit/nika"
done
if [ -x "$HERE/../../bin/nika-kit" ]; then echo "ok   the plugin pass went through bin/nika-kit"; else
  echo "FAIL bin/nika-kit is missing: the plugin pass tested the fallback twice"
  fails=$((fails + 1))
fi

# A folder name is data from the project: the command the hook tells the
# reader to run carries it shell-quoted, so pasting the line runs the check
# and nothing the name holds.
# shellcheck disable=SC2016 # the literal $(…) is the hostile name under test
ODD="$ROOT/"'$(touch pwned) flows'
mkdir -p "$ODD" "$ROOT/paste"
printf 'nika: flow\npermits: {}\ntasks: {}\n' >"$ODD/flow.nika"
for HOOK in "$HERE/../check-on-edit.sh" "$ROOT/lone/check-on-edit.sh"; do
  case "$HOOK" in "$ROOT"/*) where="lone copy" ;; *) where="in the plugin" ;; esac
  payload="$(printf '{"hook_event_name":"PostToolUse","tool_input":{"file_path":"%s"}}' "$ODD/flow.nika")"
  out="$(printf '%s' "$payload" | env -u NIKA_BIN -u CARGO_TARGET_DIR PATH="$ROOT/path-bin:/usr/bin:/bin" bash "$HOOK" 2>&1)"
  line="$(printf '%s\n' "$out" | grep -A1 're-check with the same oracle' | tail -n 1)"
  (cd "$ROOT/paste" && PATH="$ROOT/path-bin:/usr/bin:/bin" bash -c "$line" >"$ROOT/paste/out" 2>&1)
  if [ -n "$line" ] && [ ! -e "$ROOT/paste/pwned" ] && grep -qF "finding from path-bin" "$ROOT/paste/out"; then
    printf 'ok   %s · the suggested command runs the check and nothing a folder name holds\n' "$where"
  else
    printf 'FAIL %s · pasting the suggested command: %s\n' "$where" "$line"
    fails=$((fails + 1))
    rm -f "$ROOT/paste/pwned"
  fi
done

if [ "$fails" -eq 0 ]; then
  echo "all green"
else
  echo "$fails failure(s)"
  exit 1
fi
