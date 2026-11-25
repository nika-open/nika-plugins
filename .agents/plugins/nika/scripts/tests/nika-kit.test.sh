#!/usr/bin/env bash
# nika-kit.test · the resolver names the binary the work targets, says why,
# and never falls back in silence. Stub binaries only: nothing is run.
#
# A project never chooses the binary: a build under a tree's own target/ is
# never picked, a CARGO_TARGET_DIR that is relative or resolves inside the
# repository is ignored, and no hook entry point runs a binary a repository
# holds. The situations are the ones check-on-edit-oracle.test.sh plays
# against the edit hook, so the two cannot disagree without one going red.
#
# Usage: nika-kit.test.sh  (exit 0 = all green)
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/nika-kit"
ROOT="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$ROOT"' EXIT
export HOME="$ROOT/home"
mkdir -p "$HOME"
fails=0
bad() {
  printf 'FAIL %s\n' "$1"
  fails=$((fails + 1))
}

stub() { # stub <dir> <label> [feature…]
  mkdir -p "$1"
  cat >"$1/nika" <<STUB
#!/usr/bin/env bash
case "\$1 \${2:-}" in
  "--version "*) echo "nika 0.0.0 ($2)" ;;
  "help consent") case " ${*:3} " in *" consent "*) exit 0 ;; *) exit 2 ;; esac ;;
  "catalog --help") case " ${*:3} " in *" mcp-shelf "*) echo "      --mcp   list the shelf" ;; *) echo "      --json" ;; esac ;;
  *) exit 64 ;;
esac
STUB
  chmod +x "$1/nika"
}

stub "$ROOT/explicit" explicit consent mcp-shelf
stub "$ROOT/session-target/debug" session-target
stub "$ROOT/path-bin" path-bin
ENGINE="$ROOT/engine"
mkdir -p "$ENGINE/crates/nika-cli" "$ENGINE/flows"
: >"$ENGINE/crates/nika-cli/Cargo.toml"
stub "$ENGINE/target/debug" tree-build
git -C "$ENGINE" init -q
PROJECT="$ROOT/project"
mkdir -p "$PROJECT"
git -C "$PROJECT" init -q

kit() { env -u NIKA_BIN -u CARGO_TARGET_DIR PATH="$ROOT/path-bin:/usr/bin:/bin" "$@"; }
picks() { # picks <label> <location> <wanted stub> [VAR=value…]
  local label="$1" where="$2" want="$3" out
  shift 3
  out="$(kit "$@" bash "$KIT" "$where" 2>&1)"
  if printf '%s' "$out" | grep -qF "($want)" && printf '%s' "$out" | grep -q '^why: .'; then
    printf 'ok   %s\n' "$label"
  else bad "$label: wanted $want with a reason, got: $out"; fi
}

picks "NIKA_BIN wins everywhere" "$ENGINE/flows" explicit \
  NIKA_BIN="$ROOT/explicit/nika" CARGO_TARGET_DIR="$ROOT/session-target"
picks "inside the engine, the session target folder" "$ENGINE/flows" session-target \
  CARGO_TARGET_DIR="$ROOT/session-target"
picks "inside the engine, no session folder: the PATH, never the tree's own build" "$ENGINE/flows" path-bin
picks "a session folder with no build falls back to the PATH" "$ENGINE/flows" path-bin \
  CARGO_TARGET_DIR="$ROOT/empty-target"
picks "outside the engine, the session folder is not used" "$PROJECT" path-bin \
  CARGO_TARGET_DIR="$ROOT/session-target"
picks "outside the engine, NIKA_BIN names it" "$PROJECT" explicit NIKA_BIN="$ROOT/explicit/nika"
picks "a session folder inside the repository is ignored" "$ENGINE/flows" path-bin \
  CARGO_TARGET_DIR="$ENGINE/target"
ln -s "$ENGINE/target" "$ROOT/link-target"
picks "a session folder that resolves inside the repository is ignored" "$ENGINE/flows" path-bin \
  CARGO_TARGET_DIR="$ROOT/link-target"
out="$(cd "$ENGINE" && kit CARGO_TARGET_DIR="target" bash "$KIT" "$ENGINE/flows" 2>&1)"
if printf '%s' "$out" | grep -qF "(path-bin)"; then echo "ok   a relative session folder is ignored"; else
  bad "a relative session folder: $out"
fi

# The unchosen tree build is named by the default mode alone, with its pin.
out="$(kit bash "$KIT" "$ENGINE/flows" 2>&1)"
if printf '%s' "$out" | grep -qF "never chosen" && printf '%s' "$out" | grep -qF "NIKA_BIN=$ENGINE/target/debug/nika"; then
  echo "ok   the default mode names the tree's own build and how to pin it"
else bad "the unchosen build is not named: $out"; fi
out="$(kit bash "$KIT" --path "$ENGINE/flows" 2>&1)"
if [ "$out" = "$ROOT/path-bin/nika" ]; then echo "ok   --path says nothing about it"; else
  bad "--path printed more than the path: $out"
fi
out="$(kit NIKA_BIN="$ENGINE/target/debug/nika" bash "$KIT" "$ENGINE/flows" 2>&1)"
if printf '%s' "$out" | grep -qF "(tree-build)" && ! printf '%s' "$out" | grep -qF "never chosen"; then
  echo "ok   a pin on the tree's build is honoured, with no note"
else bad "a pinned tree build: $out"; fi

out="$(kit NIKA_BIN="$ROOT/absent/nika" bash "$KIT" --path "$PROJECT" 2>&1)"
rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "not an executable" && ! printf '%s' "$out" | grep -qF "path-bin"; then
  echo "ok   a broken pin is an error, not a fall back to the PATH"
else bad "a broken pin: exit $rc, $out"; fi

out="$(env -u NIKA_BIN -u CARGO_TARGET_DIR PATH="/usr/bin:/bin" bash "$KIT" --path "$PROJECT" 2>&1)"
rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "no nika binary"; then
  echo "ok   no binary anywhere says so and exits 1"
else bad "no binary: exit $rc, $out"; fi

out="$(kit bash "$KIT" --path "$PROJECT")"
if [ "$out" = "$ROOT/path-bin/nika" ]; then echo "ok   --path prints the path alone"; else
  bad "--path printed: $out"
fi

has() { # has <label> <feature> <wanted rc> [VAR=value…]
  local label="$1" feature="$2" want="$3"
  shift 3
  kit "$@" bash "$KIT" --has "$feature" "$PROJECT" >/dev/null 2>&1
  local rc=$?
  if [ "$rc" -eq "$want" ]; then echo "ok   $label"; else bad "$label: exit $rc, wanted $want"; fi
}
has "a binary with a consent verb has it" consent 0 NIKA_BIN="$ROOT/explicit/nika"
has "a binary without one does not" consent 1
has "a binary that lists the MCP shelf has it" mcp-shelf 0 NIKA_BIN="$ROOT/explicit/nika"
has "a binary that does not list it does not" mcp-shelf 1
has "no binary is neither yes nor no" consent 2 NIKA_BIN="$ROOT/absent/nika"

# ── a repository that holds an executable target/debug/nika: no hook entry
# point runs it. The planted binary leaves a sentinel when it is run; the
# PATH's binary writes down that it was asked.
HERE="$(cd "$(dirname "$KIT")/../scripts" && pwd)"
TRAP="$ROOT/trap"
SENTINEL="$ROOT/sentinel"
ASKED="$ROOT/asked"
mkdir -p "$TRAP/target/debug" "$TRAP/crates/nika-cli" "$TRAP/.nika/traces" "$TRAP/workflows" "$ROOT/calm" "$ROOT/data"
: >"$TRAP/crates/nika-cli/Cargo.toml"
git -C "$TRAP" init -q
printf '#!/usr/bin/env bash\n: >"%s"\nexit 0\n' "$SENTINEL" >"$TRAP/target/debug/nika"
chmod +x "$TRAP/target/debug/nika"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"%s"\necho "{}"\nexit 0\n' "$ASKED" >"$ROOT/calm/nika"
chmod +x "$ROOT/calm/nika"
printf 'nika: flow\npermits: {}\ntasks: {}\n' >"$TRAP/workflows/flow.nika"
printf '{"kind":"workflow_started","fields":[{"key":"workflow","value":"flow"}]}\n' >"$TRAP/.nika/traces/a.ndjson"
clean() { env -u NIKA_BIN -u CARGO_TARGET_DIR PATH="$ROOT/calm:/usr/bin:/bin" CLAUDE_PLUGIN_DATA="$ROOT/data" "$@"; }
entry() { # entry <label> <stdin payload> <command…>: run it in the trap, then look for the sentinel
  local label="$1" payload="$2"
  shift 2
  : >"$ASKED"
  (cd "$TRAP" && printf '%s' "$payload" | clean "$@" >/dev/null 2>&1)
  if [ -e "$SENTINEL" ]; then
    bad "$label ran the binary the repository holds"
    rm -f "$SENTINEL"
  elif [ -s "$ASKED" ]; then echo "ok   $label asks the PATH's binary, not the repository's"; else
    bad "$label asked no binary, so the case proves nothing"
  fi
}
out="$(cd "$TRAP" && clean bash "$KIT" --path "$TRAP")"
if [ "$out" = "$ROOT/calm/nika" ]; then echo "ok   the resolver returns the PATH's binary there"; else
  bad "the resolver returned: $out"
fi
entry "the resolver's default mode" "" bash "$KIT" "$TRAP"
entry "the feature probe" "" bash "$KIT" --has consent "$TRAP"
entry "the facts read at skill load" "" bash "$HERE/nika-facts.sh" "$TRAP"
EDIT="{\"hook_event_name\":\"PostToolUse\",\"tool_input\":{\"file_path\":\"$TRAP/workflows/flow.nika\"}}"
entry "the edit hook" "$EDIT" bash "$HERE/check-on-edit.sh"
cp "$HERE/check-on-edit.sh" "$ROOT/lone-check-on-edit.sh"
entry "the edit hook's lone copy" "$EDIT" bash "$ROOT/lone-check-on-edit.sh"
if command -v python3 >/dev/null 2>&1; then
  entry "the session start hook" "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"k1\",\"cwd\":\"$TRAP\"}" bash "$HERE/session-status.sh"
  sleep 1
  printf 'nika: flow\npermits: {}\ntasks: {}\n# edited\n' >"$TRAP/workflows/flow.nika"
  entry "the stop gate" "{\"session_id\":\"k1\",\"cwd\":\"$TRAP\",\"stop_hook_active\":false}" bash "$HERE/stop-gate.sh"
  entry "the author gate" "{\"agent_type\":\"nika:nika-author\",\"agent_id\":\"k2\",\"session_id\":\"k1\",\"cwd\":\"$TRAP\",\"last_assistant_message\":\"Wrote workflows/flow.nika.\"}" python3 "$HERE/author-stop-gate.py"
  entry "the notes kept through a compaction" "{\"session_id\":\"k1\",\"cwd\":\"$TRAP\"}" python3 "$HERE/precompact-notes.py"
  entry "the waiting-run monitor" "" env NIKA_PENDING_WATCH_ONCE=1 bash "$HERE/pending-watch.sh"
  entry "the plain verdict" "" python3 "$HERE/nika-verdict.py" workflows/flow.nika
  entry "the plan card" "" python3 "$HERE/nika-card.py" workflows/flow.nika
else
  echo "skip the python entry points: no python3 on this machine"
fi

if [ "$fails" -eq 0 ]; then echo "all green"; else
  echo "$fails failure(s)"
  exit 1
fi
