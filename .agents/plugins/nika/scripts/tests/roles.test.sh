#!/usr/bin/env bash
# roles.test · the five roles keep the choices that protect the person.
#
# Laws under test: no role names a model stronger than the session's (every
# role inherits, the scout alone names a cheaper one) · the two roles that
# only read hold no write tool · the author and the migrator start with the
# authoring skill · memory is given to the author and the debugger only,
# and a role that has it states what never goes in it.
#
# Usage: roles.test.sh  (exit 0 = all green)
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FAILS=0
bad() {
  echo "FAIL $1"
  FAILS=$((FAILS + 1))
}
front() { # front <agent> : its frontmatter
  awk 'NR == 1 && /^---$/ { inside = 1; next } inside && /^---$/ { exit } inside' "$KIT/agents/$1.md"
}
field() { # field <agent> <key> : the scalar value of one frontmatter key
  front "$1" | sed -n "s/^$2: *//p" | head -n 1
}

for role in nika-author nika-reviewer nika-debugger nika-migrator nika-scout; do
  [ -f "$KIT/agents/$role.md" ] || {
    bad "agents/$role.md is missing"
    continue
  }
  model="$(field "$role" model)"
  case "$role:$model" in
    nika-scout:haiku | *:inherit) echo "ok   $role runs on: $model" ;;
    *) bad "$role names the model '$model': a role inherits the session's model, and only the scout names a cheaper one" ;;
  esac
  [ -n "$(field "$role" effort)" ] || bad "$role states no effort"
  [ -n "$(field "$role" maxTurns)" ] || bad "$role has no turn cap"
done

for role in nika-reviewer nika-scout; do
  case "$(field "$role" tools)" in
    *Write* | *Edit*) bad "$role holds a write tool, and its job is to read" ;;
    *) echo "ok   $role holds no write tool" ;;
  esac
  [ -z "$(field "$role" memory)" ] || bad "$role was given a memory, which grants it write tools"
done

for role in nika-author nika-migrator; do
  if front "$role" | grep -qx '  - nika-authoring'; then echo "ok   $role starts with the authoring skill"; else
    bad "$role does not preload nika-authoring"
  fi
done

for role in nika-author nika-debugger; do
  [ "$(field "$role" memory)" = "project" ] || bad "$role lost its project memory"
  if grep -q 'a secret, a data value or a personal detail' "$KIT/agents/$role.md"; then
    echo "ok   $role says what never goes in its memory"
  else
    bad "$role has a memory and does not say what stays out of it"
  fi
done
[ -z "$(field nika-migrator memory)" ] || bad "nika-migrator was given a memory"

if grep -q 'the person.s sentence, word for word, and the path' "$KIT/agents/nika-reviewer.md"; then
  echo "ok   the reviewer is told it receives the sentence and the path only"
else
  bad "the reviewer no longer says what it receives"
fi

if [ "$FAILS" -eq 0 ]; then echo "all green"; else
  echo "$FAILS failure(s)"
  exit 1
fi
