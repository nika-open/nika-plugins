#!/usr/bin/env bash
# approval-rule.test · every page that can stop for the person says what
# needs their yes and what never does.
#
# A rule that only says "when authorized" makes a careful agent hold back
# on work nobody needs to approve (a check, a repair, a dry run) and still
# leaves open what does need a yes. Each entry page names both lists; the
# session map carries the short form for hosts that load nothing else.
#
# The rehearsal that never waits is bounded the same way on every page that
# states it: a model pinned on a task is called for real under the mock
# model, so a job that pins one is read with a dry run.
#
# Usage: approval-rule.test.sh  (exit 0 = all green)
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FAILS=0
bad() {
  echo "FAIL $1"
  FAILS=$((FAILS + 1))
}

for page in commands/make.md commands/run.md rules/nika-delegation.mdc \
  skills/nika-authoring/SKILL.md skills/nika-running/SKILL.md \
  skills/nika-debugging/SKILL.md skills/nika-operating/SKILL.md \
  skills/nika-migration/SKILL.md; do
  folded="$(tr '\n' ' ' <"$KIT/$page" | tr -s ' ')"
  case "$folded" in
    *"hat needs the person, and what never does"*) echo "ok   $page names both lists" ;;
    *) bad "$page can stop for the person and does not say what needs a yes and what never does" ;;
  esac
  case "$folded" in
    *"gate"*) ;;
    *) bad "$page lists what needs the person and leaves out the answer to a gate" ;;
  esac
done

for page in commands/make.md commands/improve.md rules/nika-delegation.mdc \
  skills/nika-authoring/SKILL.md skills/nika-migration/SKILL.md \
  agents/nika-reviewer.md; do
  folded="$(tr '\n' ' ' <"$KIT/$page" | tr -s ' ')"
  case "$folded" in
    *"pins no model on a task"* | *"no task pins a model"* | *"pins a model on a task"*) echo "ok   $page bounds the mock rehearsal by a pinned model" ;;
    *) bad "$page lets a job that pins a model on a task be rehearsed on the mock model" ;;
  esac
  case "$folded" in
    *"The mock replaces the model and nothing else"* | *"A mock model replaces the model only"*)
      bad "$page says the mock replaces every model, which a pinned model contradicts"
      ;;
  esac
done

map="$KIT/scripts/session-context.sh"
grep -qF 'Ask the human for:' "$map" || bad "the session map lost « Ask the human for: »"
grep -qF 'Never make them wait for:' "$map" || bad "the session map lost « Never make them wait for: »"

if [ "$FAILS" -eq 0 ]; then echo "all green"; else
  echo "$FAILS failure(s)"
  exit 1
fi
