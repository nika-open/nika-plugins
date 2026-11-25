#!/usr/bin/env bash
# manifest-counts.test.sh: the prose of every host manifest matches the tree.
#
# Each manifest description counts what the bundle carries ("5 skills",
# "3 subagents", "2 rules", "11 slash commands") and often lists the
# commands. Those numbers are prose, so nothing kept them true: the Cursor
# manifest said "4 skills" and "6 commands" while the bundle carried 5 and 9.
# The counts here are derived from the tree:
#
#   skills    skills/*/SKILL.md
#   commands  commands/*.md
#   subagents agents/*.md
#   rules     rules/*.mdc
#
# Every count a manifest states must equal the tree's, every command a
# manifest names must exist as commands/<name>.md, and a command list that
# follows a count must name exactly that many commands. The public mirror
# runs the same comparison; this catches the drift before the mirror does.
#
# Usage: manifest-counts.test.sh  (exit 0 = all green)
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
command -v python3 >/dev/null 2>&1 || {
  # Red, not a quiet pass: the runner prints only "ok" for an exit 0, so a
  # skip here would read as counts that were compared.
  echo "FAIL manifest-counts.test: python3 is absent, so no count was compared" >&2
  exit 1
}

python3 -I - "$KIT" <<'PY'
import json
import re
import sys
from pathlib import Path

kit = Path(sys.argv[1])
tree = {
    "skills": len(list(kit.glob("skills/*/SKILL.md"))),
    "commands": len(list(kit.glob("commands/*.md"))),
    "subagents": len(list(kit.glob("agents/*.md"))),
    "rules": len(list(kit.glob("rules/*.mdc"))),
}
commands = {p.stem for p in kit.glob("commands/*.md")}
manifests = [
    ".claude-plugin/plugin.json",
    ".codex-plugin/plugin.json",
    ".cursor-plugin/plugin.json",
    "plugin.json",
]
count_re = re.compile(r"\b(\d+) (slash commands|commands|skills|subagents|rules)\b")
listed_re = re.compile(r"\b(\d+) (?:slash )?commands \(([^)]*)\)")
name_re = re.compile(r"(?<![\w.])/(?:nika:)?([a-z][a-z0-9-]*)\b")
fails = 0
checked = 0


def strings(node):
    if isinstance(node, dict):
        for value in node.values():
            yield from strings(value)
    elif isinstance(node, list):
        for value in node:
            yield from strings(value)
    elif isinstance(node, str):
        yield node


def fail(message):
    global fails
    fails += 1
    print(f"FAIL {message}")


for rel in manifests:
    path = kit / rel
    if not path.is_file():
        fail(f"{rel}: the manifest is missing")
        continue
    for text in strings(json.loads(path.read_text())):
        for number, kind in count_re.findall(text):
            key = "commands" if kind.endswith("commands") else kind
            checked += 1
            if int(number) != tree[key]:
                fail(f"{rel}: says {number} {kind}, the tree carries {tree[key]}")
        for number, inner in listed_re.findall(text):
            names = name_re.findall(inner)
            if len(names) != int(number):
                fail(f"{rel}: counts {number} commands but lists {len(names)}: {inner}")
            for name in names:
                if name not in commands:
                    fail(f"{rel}: lists /{name}, which is not commands/{name}.md")

if checked == 0:
    fail("no manifest states a count: the comparison read nothing")
if fails:
    print(f"{fails} failure(s)")
    sys.exit(1)
print(
    "ok   every manifest count matches the tree "
    f"({tree['skills']} skills, {tree['commands']} commands, "
    f"{tree['subagents']} subagents, {tree['rules']} rules; {checked} counts read)"
)
print("all green")
PY
