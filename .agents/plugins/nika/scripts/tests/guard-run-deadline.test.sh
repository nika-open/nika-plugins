#!/usr/bin/env bash
# guard-run-deadline.test.sh: a judge that does not answer is refused in time.
#
# A host that times a hook out lets the action through, so the shim holds
# `nika guard` to a 20 s deadline. Past it the shim ends the judge and every
# process the judge started, and refuses with the hosts' shared blocking
# protocol (exit 2, the reason on stderr, nothing on stdout), whichever
# dialect the payload speaks. A judge that answers in time leaves nothing
# of the deadline behind.
#
# Stub judges stand in for the binary: one swallows the payload, starts a
# child and sleeps 60 s; one answers at once. The two dialects run side by
# side, so the suite costs one deadline, about 20 s. No command in a
# payload is executed.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHIM="$HERE/../guard-run.sh"
root="$(mktemp -d)"
root="$(cd "$root" && pwd -P)"
cleanup() {
  local pid
  cat "$root"/*.pids 2>/dev/null | while read -r pid; do kill -KILL "$pid" 2>/dev/null; done
  rm -rf "$root"
}
trap cleanup EXIT
mkdir -p "$root/slow" "$root/fast" "$root/home" "$root/state" "$root/tmp"
fails=0

# The slow judge records its own pid and its child's (in NIKA_TEST_PIDS when
# a case names its own file), then waits on it.
cat >"$root/slow/nika" <<EOF
#!/bin/sh
/bin/cat >/dev/null
/bin/sleep 60 &
echo "\$!" >>"\${NIKA_TEST_PIDS:-$root/pids}"
echo "\$\$" >>"\${NIKA_TEST_PIDS:-$root/pids}"
wait
EOF
printf '%s\n' '#!/bin/sh' '/bin/cat >/dev/null' "printf '{}\\n'" >"$root/fast/nika"
chmod +x "$root/slow/nika" "$root/fast/nika"

cursor='{"command":"nika run flow.nika","cwd":"/tmp"}'
claude='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"nika run flow.nika"},"cwd":"/tmp"}'

# shim <name> <judge dir> <payload> [tmpdir] [signal]: run the shim in a
# process group of its own (job control), so whatever it leaves behind can be
# found afterwards. With a signal, send it to the shim once its judge has
# started: "TERM" to the shim alone, "-TERM" to the shim's whole group, the
# way a host stops a hook. Writes <name>.out, <name>.err, <name>.rc,
# <name>.secs, <name>.pgid and <name>.pids (what the judge started).
shim() {
  local name="$1" judge="$2" payload="$3" tmp="${4:-$root/tmp}" signal="${5:-}"
  local start pid rc=0 tries=0
  start="$(date +%s)"
  printf '%s' "$payload" >"$root/$name.in"
  : >"$root/$name.pids"
  set -m
  env -i PATH="$judge:/usr/bin:/bin" HOME="$root/home" XDG_STATE_HOME="$root/state" \
    TMPDIR="$tmp" NIKA_TEST_PIDS="$root/$name.pids" \
    /bin/bash "$SHIM" <"$root/$name.in" >"$root/$name.out" 2>"$root/$name.err" &
  pid=$!
  set +m
  printf '%s\n' "$pid" >"$root/$name.pgid"
  if [ -n "$signal" ]; then
    while [ "$(wc -l <"$root/$name.pids" | tr -d ' ')" -lt 2 ] && [ "$tries" -lt 100 ]; do
      sleep 0.05
      tries=$((tries + 1))
    done
    case "$signal" in
      -*) kill "-${signal#-}" -- "-$pid" 2>/dev/null ;;
      *) kill "-$signal" "$pid" 2>/dev/null ;;
    esac
  fi
  wait "$pid" || rc=$?
  printf '%s\n' "$rc" >"$root/$name.rc"
  printf '%s\n' "$(($(date +%s) - start))" >"$root/$name.secs"
}

# left <pgid>: how many processes of that group still exist, read again for
# up to two seconds while the count is not zero (a process that was just
# killed can still be listed for a moment).
left() {
  local tries=0 count
  while :; do
    count="$(ps -axo pgid= | awk -v g="$1" '$1 == g' | wc -l | tr -d ' ')"
    [ "$count" = 0 ] || [ "$tries" -ge 20 ] && break
    sleep 0.1
    tries=$((tries + 1))
  done
  printf '%s\n' "$count"
}

# gone <pid>...: true when every pid has ended (a killed child may take a
# moment to be reaped once its parent is gone).
gone() {
  local tries=0 pid alive
  while [ "$tries" -lt 20 ]; do
    alive=""
    for pid in "$@"; do kill -0 "$pid" 2>/dev/null && alive=1; done
    [ -n "$alive" ] || return 0
    sleep 0.1
    tries=$((tries + 1))
  done
  return 1
}

check() {
  if [ "$2" = yes ]; then
    printf 'ok    %s\n' "$1"
  else
    printf 'FAIL  %s\n      %s\n' "$1" "$3" >&2
    fails=$((fails + 1))
  fi
}

shim slow-cursor "$root/slow" "$cursor" &
first=$!
shim slow-claude "$root/slow" "$claude" &
second=$!
wait "$first" "$second"

for dialect in cursor claude; do
  name="slow-$dialect"
  rc="$(cat "$root/$name.rc")"
  secs="$(cat "$root/$name.secs")"
  err="$(cat "$root/$name.err")"
  out="$(cat "$root/$name.out")"
  want='guard_unavailable: nika guard did not answer within 20 s'
  [ "$rc" = 2 ] && ok=yes || ok=no
  check "$dialect · a silent judge is refused with the blocking exit" "$ok" "rc=$rc"
  [ -z "$out" ] && [ "${err#"$want"}" != "$err" ] && ok=yes || ok=no
  check "$dialect · the refusal names the deadline, on stderr only" "$ok" "stdout=$out stderr=$err"
  [ "$secs" -ge 19 ] && [ "$secs" -lt 25 ] && ok=yes || ok=no
  check "$dialect · the shim waits the deadline, and returns before 25 s" "$ok" "returned after ${secs}s"
  [ "$(left "$(cat "$root/$name.pgid")")" = 0 ] && ok=yes || ok=no
  check "$dialect · the shim leaves no process of its own behind" "$ok" "$(left "$(cat "$root/$name.pgid")") left"
done
cat "$root/slow-cursor.pids" "$root/slow-claude.pids" >"$root/pids"
# shellcheck disable=SC2046 # one pid per line, digits only
gone $(cat "$root/pids") && ok=yes || ok=no
check "the judge and the child it started are gone" "$ok" "still running: $(tr '\n' ' ' <"$root/pids")"
[ "$(wc -l <"$root/pids" | tr -d ' ')" = 4 ] && ok=yes || ok=no
check "both slow judges did start (two pids each)" "$ok" "pids: $(tr '\n' ' ' <"$root/pids")"

# A host that stops the hook: TERM to the shim alone, then to its whole
# group. The judge sits in a group of its own, so only the shim's own exit
# path can end it; the shim still exits with the blocking code. Then each
# other signal a host, a timer or a resource limit sends to end a process:
# on bash 3.2 one the hook did not catch would end it with 128 + its
# number, which hosts read as a non-blocking error.
for signal in TERM -TERM USR1 PIPE HUP INT QUIT ALRM USR2 XCPU XFSZ VTALRM PROF; do
  name="stopped${signal}"
  shim "$name" "$root/slow" "$claude" "$root/tmp" "$signal"
  rc="$(cat "$root/$name.rc")"
  secs="$(cat "$root/$name.secs")"
  [ "$rc" = 2 ] && [ ! -s "$root/$name.out" ] && ok=yes || ok=no
  check "$signal · a stopped hook exits with the blocking code" "$ok" "rc=$rc stdout=$(cat "$root/$name.out")"
  [ "$secs" -lt 5 ] && ok=yes || ok=no
  check "$signal · a stopped hook ends at once, not at the deadline" "$ok" "returned after ${secs}s"
  [ "$(wc -l <"$root/$name.pids" | tr -d ' ')" = 2 ] && ok=yes || ok=no
  check "$signal · the judge had started when the hook was stopped" "$ok" "pids: $(tr '\n' ' ' <"$root/$name.pids")"
  # shellcheck disable=SC2046 # one pid per line, digits only
  gone $(cat "$root/$name.pids") && ok=yes || ok=no
  check "$signal · the judge and its child end with the hook" "$ok" "still running: $(tr '\n' ' ' <"$root/$name.pids")"
  judge_group="$(sed -n 2p "$root/$name.pids")"
  [ "$(left "$judge_group")" = 0 ] && [ "$(left "$(cat "$root/$name.pgid")")" = 0 ] && ok=yes || ok=no
  check "$signal · no process of the hook's or the judge's group is left" "$ok" "judge group $(left "$judge_group"), hook group $(left "$(cat "$root/$name.pgid")")"
done

# The signal trap is the first command after the clean-PATH block, so no
# step of the hook runs before it: read from the hook itself, then shown
# with a copy that signals itself right before the next step after it.
trap_line="trap 'exit 2' HUP INT QUIT TERM PIPE ALRM USR1 USR2 XCPU XFSZ VTALRM PROF"
first="$(awk 'found && $0 !~ /^(#|$)/ { print; exit } /^# <<< nika-clean-path$/ { found = 1 }' "$SHIM")"
[ "$first" = "$trap_line" ] && ok=yes || ok=no
check "the signal trap is the first command after the PATH block" "$ok" "first command: $first"
[ "$(grep -c "^trap 'exit 2'" "$SHIM")" = 1 ] && ok=yes || ok=no
check "the hook sets that signal trap once" "$ok" "$(grep -c "^trap 'exit 2'" "$SHIM") trap lines"
SHIM_REAL="$SHIM"
SHIM="$root/early.sh"
awk '/^set -uo pipefail$/ { print "kill -USR1 $$" } { print }' "$SHIM_REAL" >"$SHIM"
[ "$(grep -c '^kill -USR1 \$\$$' "$SHIM")" = 1 ] && ok=yes || ok=no
check "the early copy signals itself before its first step" "$ok" "no set -uo pipefail line to precede"
shim early "$root/fast" "$claude"
SHIM="$SHIM_REAL"
rc="$(cat "$root/early.rc")"
[ "$rc" = 2 ] && [ ! -s "$root/early.out" ] && ok=yes || ok=no
check "a signal right after the PATH block ends the hook with the blocking exit" "$ok" "rc=$rc stdout=$(cat "$root/early.out")"

# An unforeseen failure once the judge has started: a copy of the hook with
# `exit 1` right after the judge starts. The trap ends the judge and turns
# the 1, which every host reads as a non-blocking error, into the blocking 2.
SHIM_REAL="$SHIM"
SHIM="$root/injected.sh"
awk '{ print } /^judge=\$!$/ { print "exit 1" }' "$SHIM_REAL" >"$SHIM"
[ "$(grep -c '^exit 1$' "$SHIM")" = 1 ] && ok=yes || ok=no
check "the injected copy fails right after the judge starts" "$ok" "no judge=\$! line to follow"
shim injected "$root/slow" "$claude"
SHIM="$SHIM_REAL"
rc="$(cat "$root/injected.rc")"
secs="$(cat "$root/injected.secs")"
[ "$rc" = 2 ] && [ ! -s "$root/injected.out" ] && [ "$secs" -lt 5 ] && ok=yes || ok=no
check "an unforeseen exit 1 after the judge starts becomes the blocking exit 2" "$ok" "rc=$rc after ${secs}s stdout=$(cat "$root/injected.out")"
# shellcheck disable=SC2046 # one pid per line, digits only
gone $(cat "$root/injected.pids") && ok=yes || ok=no
check "the judge it had started ends with it" "$ok" "still running: $(tr '\n' ' ' <"$root/injected.pids")"

shim fast "$root/fast" "$claude"
rc="$(cat "$root/fast.rc")"
secs="$(cat "$root/fast.secs")"
[ "$rc" = 0 ] && [ "$(cat "$root/fast.out")" = '{}' ] && ok=yes || ok=no
check "a judge that answers keeps its verdict" "$ok" "rc=$rc stdout=$(cat "$root/fast.out")"
[ "$secs" -le 2 ] && ok=yes || ok=no
check "a judge that answers is not held to the deadline" "$ok" "returned after ${secs}s"
[ "$(left "$(cat "$root/fast.pgid")")" = 0 ] && ok=yes || ok=no
check "a judge that answers leaves no deadline timer behind" "$ok" "$(left "$(cat "$root/fast.pgid")") left"
[ ! -s "$root/fast.err" ] && ok=yes || ok=no
check "a judge that answers adds nothing to stderr" "$ok" "stderr=$(cat "$root/fast.err")"
leftover="$(find "$root/tmp" -mindepth 1 -maxdepth 1)"
[ -z "$leftover" ] && ok=yes || ok=no
check "no run leaves its temporary folder behind" "$ok" "left: $leftover"

# Without a temporary folder the deadline cannot be kept: the shim refuses
# rather than call a judge it could not stop.
shim notmp "$root/fast" "$claude" "$root/missing"
rc="$(cat "$root/notmp.rc")"
err="$(cat "$root/notmp.err")"
want='guard_unavailable: the hook could not make a temporary folder'
[ "$rc" = 2 ] && [ ! -s "$root/notmp.out" ] && [ "${err#"$want"}" != "$err" ] && ok=yes || ok=no
check "no temporary folder: refused, the judge is never called" "$ok" "rc=$rc stderr=$err"

# A relative TMPDIR names a folder of the one the hook runs in, the open
# project: the hook keeps the judge's answer under /tmp instead. The judge
# looks for the hook's folder in the project while it runs.
mkdir -p "$root/proj/tmp" "$root/peek"
cat >"$root/peek/nika" <<EOF
#!/bin/sh
/bin/cat >/dev/null
/bin/ls -d "\$PWD"/tmp/nika-guard.* >>"$root/peek.seen" 2>/dev/null
printf '{}\\n'
EOF
chmod +x "$root/peek/nika"
: >"$root/peek.seen"
(cd "$root/proj" && shim reltmp "$root/peek" "$claude" tmp)
rc="$(cat "$root/reltmp.rc")"
[ "$rc" = 0 ] && [ "$(cat "$root/reltmp.out")" = '{}' ] && ok=yes || ok=no
check "a relative TMPDIR: the judge is still called and its verdict passed on" "$ok" "rc=$rc stdout=$(cat "$root/reltmp.out") stderr=$(cat "$root/reltmp.err")"
leftover="$(find "$root/proj/tmp" -mindepth 1)"
[ ! -s "$root/peek.seen" ] && [ -z "$leftover" ] && ok=yes || ok=no
check "a relative TMPDIR: nothing of the hook's goes in the project" "$ok" "seen: $(cat "$root/peek.seen") left: $leftover"

# A verdict the hook cannot write is no answer: with its stdout closed, an
# allow the judge gave ends the hook with the blocking exit, not 0.
printf '%s' "$claude" >"$root/closed.in"
closed_rc=0
env -i PATH="$root/fast:/usr/bin:/bin" HOME="$root/home" XDG_STATE_HOME="$root/state" \
  TMPDIR="$root/tmp" /bin/bash "$SHIM" <"$root/closed.in" >&- 2>"$root/closed.err" || closed_rc=$?
[ "$closed_rc" = 2 ] && ok=yes || ok=no
check "a verdict that cannot be written ends the hook with the blocking exit" "$ok" "rc=$closed_rc stderr=$(cat "$root/closed.err")"

# The folder a refusal names comes from the environment: it is shown with
# printable characters only, on one line.
shim oddtmp "$root/fast" "$claude" "$root/missing$(printf '\033[31m\nforged line')"
rc="$(cat "$root/oddtmp.rc")"
lines="$(wc -l <"$root/oddtmp.err" | tr -d ' ')"
[ "$rc" = 2 ] && [ "$lines" = 1 ] && ! grep -q "$(printf '\033')" "$root/oddtmp.err" && ok=yes || ok=no
check "an odd TMPDIR is shown on one printable line" "$ok" "rc=$rc lines=$lines stderr=$(cat -v "$root/oddtmp.err")"

# A judge that exits 0 or 2 without a verdict is no judge: a banner or a
# message in place of the JSON object, an answer cut short before its end
# of line, or one larger than any verdict is refused like a broken binary,
# never passed on as the host's answer. The binary named is absolute (the
# first nika on an absolute PATH folder), so only its answer is at fault.
mkdir -p "$root/banner" "$root/banner2" "$root/allow"
printf '%s\n' '#!/bin/sh' '/bin/cat >/dev/null' 'echo "nika 0.0.0 — welcome"' 'exit 0' >"$root/banner/nika"
printf '%s\n' '#!/bin/sh' '/bin/cat >/dev/null' 'echo "denied, see the docs"' 'exit 2' >"$root/banner2/nika"
printf '%s\n' '#!/bin/sh' '/bin/cat >/dev/null' "printf '{\"permission\":\"allow\"}\\n'" >"$root/allow/nika"
chmod +x "$root/banner/nika" "$root/banner2/nika" "$root/allow/nika"
for case in banner:0 banner2:2; do
  name="${case%%:*}"
  shim "$name" "$root/$name" "$cursor"
  rc="$(cat "$root/$name.rc")"
  err="$(cat "$root/$name.err")"
  want="guard_unavailable: nika guard failed (exit ${case#*:}, an answer that is not a verdict)"
  [ "$rc" = 2 ] && [ ! -s "$root/$name.out" ] && [ "${err#"$want"}" != "$err" ] && ok=yes || ok=no
  check "a judge's exit ${case#*:} without a JSON verdict is refused" "$ok" "rc=$rc stdout=$(cat "$root/$name.out") stderr=$err"
done
mkdir -p "$root/cut" "$root/huge"
printf '%s\n' '#!/bin/sh' '/bin/cat >/dev/null' "printf '{\"permission\":\"allow\"}'" >"$root/cut/nika"
cat >"$root/huge/nika" <<'EOF'
#!/bin/sh
/bin/cat >/dev/null
/usr/bin/awk 'BEGIN { s = "x"; while (length(s) < 17000) s = s s; printf "{\"permission\":\"allow\",\"note\":\"%s\"}\n", s }'
EOF
chmod +x "$root/cut/nika" "$root/huge/nika"
for case in cut:"an answer cut short (its line does not end)" huge:"an answer longer than any verdict"; do
  name="${case%%:*}"
  shim "$name" "$root/$name" "$cursor"
  rc="$(cat "$root/$name.rc")"
  err="$(cat "$root/$name.err")"
  want="guard_unavailable: nika guard failed (exit 0, ${case#*:})"
  [ "$rc" = 2 ] && [ ! -s "$root/$name.out" ] && [ "${err#"$want"}" != "$err" ] && ok=yes || ok=no
  check "a judge's exit 0 with ${case#*:} is refused" "$ok" "rc=$rc stdout=$(head -c 200 "$root/$name.out") stderr=$err"
done
shim allow "$root/allow" "$cursor"
rc="$(cat "$root/allow.rc")"
[ "$rc" = 0 ] && [ "$(cat "$root/allow.out")" = '{"permission":"allow"}' ] && ok=yes || ok=no
check "a JSON verdict on exit 0 is passed on as it is" "$ok" "rc=$rc stdout=$(cat "$root/allow.out")"

if [ "$fails" -ne 0 ]; then
  printf 'FAIL  %s deadline control(s)\n' "$fails" >&2
  exit 1
fi
printf 'OK  the guard deadline holds in both dialects; no command was executed\n'
