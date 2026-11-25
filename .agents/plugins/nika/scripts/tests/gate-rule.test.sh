#!/usr/bin/env bash
# gate-rule.test · the gate rule is stated once and linked, never restated.
#
# Eight pages each carried their own paragraph on when a human gate
# belongs, and the paragraphs drifted apart: some asked for two conditions
# at once, some for either, and one sentence ("a flow the check does not
# refuse needs no gate") left an irreversible effect ungated. The rule now
# lives in job-anatomy.md; every other page names that section.
#
# Usage: gate-rule.test.sh  (exit 0 = all green)
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RULE='Approve once, then let it run'
FAILS=0
bad() {
  echo "FAIL $1"
  FAILS=$((FAILS + 1))
}

anatomy="$KIT/skills/nika-authoring/references/job-anatomy.md"
grep -q "^### $RULE\$" "$anatomy" || bad "job-anatomy.md lost the section « $RULE »"
for ground in 'requires it' 'A send' 'cannot be undone' 'is not a send'; do
  grep -qF -- "$ground" "$anatomy" || bad "the rule no longer names: $ground"
done

if hits="$(grep -rIl -i --include='*.md' --include='*.mdc' --include='*.sh' --exclude-dir=tests -- 'needs no gate' "$KIT")"; then
  bad "the retired sentence « needs no gate » is back in: $hits"
fi

for page in commands/make.md commands/capture.md commands/ideas.md commands/run.md \
  agents/nika-author.md skills/nika-authoring/SKILL.md skills/nika-running/SKILL.md \
  skills/nika-authoring/references/capabilities.md; do
  folded="$(tr '\n' ' ' <"$KIT/$page" | tr -s ' ')"
  case "$folded" in
    *"Approve once, then let it run"*) ;;
    *) bad "$page speaks of gates without naming the rule's section" ;;
  esac
done

if [ "$FAILS" -eq 0 ]; then echo "all green"; else
  echo "$FAILS failure(s)"
  exit 1
fi
