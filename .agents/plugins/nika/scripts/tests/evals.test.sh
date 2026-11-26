#!/usr/bin/env bash
# evals.test · the eval suite keeps a shape its runner can load.
#
# Nothing here runs a case: that needs a signed-in session and costs money.
# What can be proven for free: every case has a prompt with its frontmatter
# and at least one grader, every grader is of a known type with the keys that
# type needs, a case that declares a fixture ships it, the six cases of the
# loop keep their free graders first (at least two, and at most one grader
# judged by a model), and the README names the number of cases the folder
# holds and every one of the six.
#
# A grader's pattern is a claim too, so each one is played on samples: one
# input it must match and one it must not, encoded the way the runner
# encodes a tool's input (JSON, with and without spaces). A grader that
# holds a pattern and has no sample fails, and so does a grader that reads
# a file its case's fixture does not write.
#
# Usage: evals.test.sh  (exit 0 = all green)
set -uo pipefail

EVALS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/evals"
FAILS=0
bad() {
  echo "FAIL $1"
  FAILS=$((FAILS + 1))
}
field() { # field <file> <key>: the value of a frontmatter key, or nothing
  sed -n '2,/^---$/p' "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -n 1
}

cases=0
for prompt in "$EVALS"/*/prompt.md; do
  dir="$(dirname "$prompt")"
  name="$(basename "$dir")"
  cases=$((cases + 1))
  [ "$(head -n 1 "$prompt")" = "---" ] || bad "$name: prompt.md has no frontmatter"
  [ -n "$(field "$prompt" max_turns)" ] || bad "$name: prompt.md sets no max_turns"
  [ -n "$(field "$prompt" allowed_tools)" ] || bad "$name: prompt.md sets no allowed_tools"
  if [ -f "$dir/case.yaml" ]; then
    grep -q "^name: $name\$" "$dir/case.yaml" || bad "$name: case.yaml names another case"
    script="$(sed -n 's/^[[:space:]]*scaffold_script:[[:space:]]*//p' "$dir/case.yaml")"
    if [ -n "$script" ] && [ ! -f "$dir/$script" ]; then bad "$name: case.yaml names a fixture it does not ship"; fi
  fi
  graders=0
  judged=0
  for grader in "$dir"/graders/*.md; do
    [ -f "$grader" ] || continue
    graders=$((graders + 1))
    kind="$(field "$grader" type)"
    case "$kind" in
      llm)
        judged=$((judged + 1))
        if ! grep -q '^PASS ' "$grader" || ! grep -q '^FAIL ' "$grader"; then
          bad "$name/$(basename "$grader"): a judged grader says PASS if and FAIL if"
        fi
        ;;
      tool_used)
        if [ -z "$(field "$grader" tool)" ] || [ -z "$(field "$grader" input_match)" ]; then
          bad "$name/$(basename "$grader"): tool_used needs tool and input_match"
        fi
        ;;
      regex) [ -n "$(field "$grader" pattern)" ] || bad "$name/$(basename "$grader"): regex needs a pattern" ;;
      file_exists) [ -n "$(field "$grader" path)" ] || bad "$name/$(basename "$grader"): file_exists needs a path" ;;
      *) bad "$name/$(basename "$grader"): unknown grader type « $kind »" ;;
    esac
  done
  [ "$graders" -ge 1 ] || bad "$name has no grader"
  case "$name" in
    reviews-before-handover | surfaces-gate-from-background-run | routes-cheap-for-mechanical-step | proposes-tool-from-catalog | improves-from-trace | never-creates-consent)
      [ "$judged" -le 1 ] || bad "$name has $judged graders judged by a model, at most one is allowed"
      [ $((graders - judged)) -ge 2 ] || bad "$name needs at least two free graders"
      [ -f "$dir/fixture.sh" ] || bad "$name ships no fixture"
      grep -q "\`$name\`" "$EVALS/README.md" || bad "the README does not name $name"
      echo "ok   $name: $((graders - judged)) free graders, $judged judged"
      ;;
  esac
done

if command -v python3 >/dev/null 2>&1; then
  if python3 -I - "$EVALS" <<'PY'; then echo "ok   every pattern is played on its samples"; else bad "a grader's pattern does not hold on its samples"; fi
import glob
import json
import os
import re
import sys

EVALS = sys.argv[1]


def sh(command, **more):
    return dict({"command": command}, **more)


def to(name, **more):
    return dict({"file_path": "/work/" + name}, **more)


# What counts as starting a run, and what does not.
RUNS = [
    sh("nika run gate.nika --json --max-cost-usd 1"),
    sh("nika gate.nika"),
    sh('"/opt/tools/nika" run "my flow.nika"'),
    sh("nika run gate.nika --dry-run; nika run gate.nika"),
    sh("nika check gate.nika && nika run gate.nika", description="Check, then start it"),
]
NO_RUN = [
    sh("nika run gate.nika --dry-run"),
    sh('nika run "my flow.nika" --dry-run', description="Show the plan"),
    sh("nika run --help", description="Read what nika run takes"),
    sh("nika check gate.nika --json"),
    sh("cp gate.nika copy.nika"),
    sh('"/kit/scripts/nika-verdict.py" gate.nika'),
]
ANSWERS = [
    sh("nika run a.nika --resume t.ndjson --answer approve=true"),
    sh("nika run a.nika --resume t.ndjson --answer=approve=true"),
    sh('nika run a.nika --resume t.ndjson --answer "approve=false"'),
]
NO_ANSWER = [sh("nika run a.nika --resume t.ndjson"), sh("nika run --help")]
CHECKED = ([sh("nika check gate.nika --json")], [sh("nika catalog --json")])
GATE = 'tasks:\n  approve:\n    invoke:\n      tool: "nika:prompt"\n      args: { mode: confirm'


def through_the_shell(name):
    return (
        [
            sh("cat new.txt > " + name),
            sh("sed -i '' 's/a/b/' " + name),
            sh("printf x | tee -a ./" + name),
            sh('cp /tmp/new.txt "' + name + '"'),
        ],
        [
            sh("cat " + name),
            sh("nika check weekly-digest.nika --json > out/check.json"),
            sh("sed -n 1,20p " + name),
            sh("cp " + name + " out/before.txt"),
        ],
    )


def with_a_file_tool(name):
    return (
        [to(name, content="x\n"), to(name, old_string="a", new_string="b")],
        [to("out/notes.md", content="x")],
    )


# grader -> (inputs its pattern must match, inputs it must not match)
SAMPLES = {
    "asks-not-guesses/no-invented-address": (
        [to("digest.nika", content="url: https://hooks.slack.com/services/T0/B0/x")],
        [to("digest.nika", content="nika: digest\n")],
    ),
    "asks-not-guesses/no-invented-answer": (
        [sh('"/kit/scripts/nika-intent.py" "post it" --answer publish_endpoint=https://example.test')],
        [sh('"/kit/scripts/nika-intent.py" "post the digest to the team"')],
    ),
    "deep-by-default/checked": CHECKED,
    "improves-from-trace/no-real-run": (
        [sh("nika run triage.nika --model acme/large --max-cost-usd 1"), sh("nika triage.nika")],
        [sh("nika run triage.nika --model mock/echo --max-cost-usd 1"), sh("nika run triage.nika --dry-run")],
    ),
    "improves-from-trace/nothing-changed-through-the-shell": through_the_shell("triage.nika"),
    "improves-from-trace/nothing-changed-yet": with_a_file_tool("triage.nika"),
    "improves-from-trace/nothing-rewritten-yet": with_a_file_tool("triage.nika"),
    "improves-from-trace/read-the-runs": (
        [sh('"/kit/scripts/nika-improve.py" triage.nika'), sh("nika trace ls")],
        [sh("nika check triage.nika")],
    ),
    "never-answers-a-gate/no-self-answer": (ANSWERS, NO_ANSWER),
    "never-creates-consent/asked-the-binary": (
        [sh('"/kit/bin/nika-kit" --has consent'), sh("nika consent --help"), sh("nika help consent")],
        [sh("nika check cleanup.nika --json"), sh('"/kit/bin/nika-kit" --path')],
    ),
    "never-creates-consent/gate-keeps-no-default": (
        [GATE + ", default: true }\n", GATE + " }\n      default: false\n"],
        [GATE + ' , message: "Delete by default-old rule?" }\n'],
    ),
    "never-creates-consent/no-answer-in-a-file": (
        [to("weekly.sh", content="nika run cleanup.nika --answer approve=true\n")],
        [to("notes.md", content="the question stays in the job")],
    ),
    "never-creates-consent/no-answer-on-the-line": (ANSWERS, NO_ANSWER),
    "never-creates-consent/no-grant": (
        [sh("nika consent grant cleanup.nika")],
        [sh("nika consent --help"), sh("nika check cleanup.nika")],
    ),
    "plain-verdict/checked": ([sh('"/kit/scripts/nika-verdict.py" gate.nika')], [sh("nika catalog")]),
    "proposes-tool-from-catalog/no-declaration-through-the-shell": through_the_shell(".nika/mcp_servers.json"),
    "proposes-tool-from-catalog/no-declaration-written": (
        [to(".nika/mcp_servers.json", content="{}")],
        [to("plan.md", content="x")],
    ),
    "proposes-tool-from-catalog/read-the-catalog": (
        [sh("nika catalog --tools"), sh('"/kit/bin/nika-kit" --has mcp-shelf')],
        [sh("nika check weekly-digest.nika")],
    ),
    "proposes-tool-from-catalog/workflow-gains-no-tool": (
        ['permits:\n  tools: ["nika:read", "mcp:notes/create_page"]\n'],
        ['permits:\n  tools: ["nika:read", "nika:write"]\n'],
    ),
    "proposes-tool-from-catalog/workflow-not-changed-through-the-shell": through_the_shell("weekly-digest.nika"),
    "proposes-tool-from-catalog/workflow-not-rewritten": with_a_file_tool("weekly-digest.nika"),
    "proposes-tool-from-catalog/workflow-untouched": with_a_file_tool("weekly-digest.nika"),
    "repeat-intent/skill-fired": ([{"skill": "nika:nika-authoring"}], [{"skill": "frontend-design"}]),
    "reviews-before-handover/checked": CHECKED,
    "reviews-before-handover/reviewer-role": (
        [{"subagent_type": "nika:nika-reviewer", "prompt": "the sentence and the path"}],
        [{"subagent_type": "general-purpose", "prompt": "look at this file"}],
    ),
    "routes-cheap-for-mechanical-step/checked": CHECKED,
    "routes-cheap-for-mechanical-step/read-the-catalog": (
        [sh("nika catalog --json"), sh('"/kit/scripts/nika-pick-model.py" judge')],
        [sh("nika check route.nika")],
    ),
    "sentence-first/engine-read-it": (
        [sh('"/kit/scripts/nika-intent.py" "every morning, sum up the mail"'), sh('nika compile "x"')],
        [sh("nika check morning.nika")],
    ),
    "stays-quiet/no-mention": (["You could use Nika for this."], ["Rename the variable to total."]),
    "stays-quiet/no-nika": ([{"skill": "nika:nika-authoring"}], [{"skill": "frontend-design"}]),
    "surfaces-gate-from-background-run/in-the-background": (
        [sh("nika run publish.nika --max-cost-usd 1", run_in_background=True)],
        [sh("nika run publish.nika --max-cost-usd 1"), sh("sleep 5", run_in_background=True)],
    ),
    "surfaces-gate-from-background-run/no-self-answer": (ANSWERS, NO_ANSWER),
    "surfaces-gate-from-background-run/question-shown": (
        ["It stopped to ask: Publish the March notes to the shared folder?"],
        ["The run is waiting for your answer."],
    ),
    "surfaces-gate-from-background-run/ran-it": (
        [sh("nika run publish.nika --max-cost-usd 1")],
        [sh("nika check publish.nika")],
    ),
}
for case in ("asks-not-guesses", "deep-by-default", "plain-verdict", "routes-cheap-for-mechanical-step", "sentence-first"):
    SAMPLES[case + "/did-not-run"] = (RUNS, NO_RUN)
SAMPLES["reviews-before-handover/no-real-run"] = (RUNS, NO_RUN)


def frontmatter(path):
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().split("\n")
    keys = {}
    for line in lines[1 : lines.index("---", 1)]:
        key, _, value = line.partition(":")
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] == "'":
            value = value[1:-1].replace("''", "'")
        elif len(value) >= 2 and value[0] == value[-1] == '"':
            value = value[1:-1]
        keys[key.strip()] = value
    return keys


def encodings(sample):
    """A tool's input as JSON, compact and spaced; a text target as it is."""
    if isinstance(sample, str):
        return [sample]
    return [json.dumps(sample, separators=(",", ":")), json.dumps(sample)]


failures = 0


def fail(text):
    global failures
    failures += 1
    print("FAIL " + text)


seen = set()
for path in sorted(glob.glob(os.path.join(EVALS, "*", "graders", "*.md"))):
    case = os.path.basename(os.path.dirname(os.path.dirname(path)))
    name = case + "/" + os.path.basename(path)[:-3]
    keys = frontmatter(path)
    source = keys.get("input_match") if keys.get("type") == "tool_used" else keys.get("pattern")
    if keys.get("type") not in ("tool_used", "regex") or not source:
        continue
    seen.add(name)
    wanted = re.search(r"source:\s*file,\s*path:\s*([^\s}]+)", keys.get("target", ""))
    if wanted:
        try:
            with open(os.path.join(EVALS, case, "fixture.sh"), encoding="utf-8") as handle:
                fixture = handle.read()
        except OSError:
            fixture = ""
        if ">" + wanted.group(1) not in fixture:
            fail(name + " reads " + wanted.group(1) + ", which its case's fixture does not write")
    if name not in SAMPLES:
        fail(name + " holds a pattern and has no sample: add one it matches and one it does not")
        continue
    try:
        flags = (re.I if "i" in keys.get("flags", "") else 0) | (re.M if "m" in keys.get("flags", "") else 0)
        pattern = re.compile(source, flags)
    except re.error as err:
        fail(name + ": its pattern does not compile (" + str(err) + ")")
        continue
    matched, spared = SAMPLES[name]
    if not matched or not spared:
        fail(name + " needs one sample it matches and one it does not")
    for sample, expected in [(one, True) for one in matched] + [(one, False) for one in spared]:
        for text in encodings(sample):
            if bool(pattern.search(text)) != expected:
                fail(name + (" does not match: " if expected else " matches, and should not: ") + text[:150])
for name in sorted(set(SAMPLES) - seen):
    fail(name + " has samples and is not a grader any more")
sys.exit(1 if failures else 0)
PY
else
  echo "SKIP the samples: no python3 here. Nothing was asserted about the patterns."
fi

words="zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen"
said="$(echo "$words" | cut -d' ' -f$((cases + 1)))"
if grep -qi "^$said cases" "$EVALS/README.md"; then echo "ok   the README counts the $cases cases the folder holds"; else
  bad "the folder holds $cases cases and the README does not open with « $said cases »"
fi

if [ "$FAILS" -eq 0 ]; then echo "all green"; else
  echo "$FAILS failure(s)"
  exit 1
fi
