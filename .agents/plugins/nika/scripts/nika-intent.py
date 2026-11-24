#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""nika-intent — let the engine read the user's own sentence, then say what
it understood in plain words.

`nika compile "<sentence>" --json` reads a bounded request with no model
call: it cuts the sentence into pieces, places each piece on a step, works
out the tightest permits, reads a schedule down to its cron line, and lists
the questions only a person can answer. This helper turns that document
into a few lines a person can check: which words became which step, which
words were left out, what the model will be told, and what to ask.

Usage:
  nika-intent.py "<the user's sentence>" [--answer KEY=VALUE ...]
                 [--write FILE.nika] [--json]
  nika-intent.py --from-hook      UserPromptSubmit payload on stdin; prints
                                  a hook envelope, or nothing

Exit: 0 ready · 2 needs answers from the user · 3 the engine cannot read
this sentence on its own (write the workflow by hand) · 1 error.

Laws: the sentence is passed as one argument, never through a shell · an
answer is never invented here · `--from-hook` runs in a scratch folder so a
hint never creates a `.nika/` folder in somebody's project.
"""
import json
import os
import re
import subprocess
import sys
import tempfile

KIND_WORDS = {
    "transformation": "work for the model",
    "effect": "something written or sent",
    "trigger": "a schedule",
    "gate": "a question asked first",
}
# The engine lowers several verbs to one generic instruction, "Draft the
# following: …". When the user's verb was not a writing verb ("summarize it
# in five lines" → "Draft the following: it in five lines"), the instruction
# no longer says what to do with the text. That is a fact the helper can
# state: the user's verb is absent from what the model will be told.
WRITING_VERBS = {
    "write", "draft", "compose", "prepare", "produce", "create", "generate",
    "écris", "ecris", "rédige", "redige", "prépare", "prepare", "compose", "crée", "cree", "génère", "genere",
}


def compile_intent(intent, answers, dest, cwd, timeout=30):
    """One `nika compile --json` call. Returns (document, error text)."""
    argv = ["nika", "compile", "--json"]
    for key, value in answers:
        argv += ["--answer", "%s=%s" % (key, value)]
    argv.append("--")
    argv.append(intent)
    if dest:
        argv.append(dest)
    try:
        done = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        return None, "the nika program is not on PATH"
    except subprocess.TimeoutExpired:
        return None, "nika compile did not answer in %s seconds" % timeout
    try:
        return json.loads(done.stdout), None
    except ValueError:
        lines = (done.stderr or done.stdout or "").strip().splitlines()
        return None, lines[0] if lines else "nika compile printed nothing"


def as_json_literal(value):
    """`model=mock/echo` → `"mock/echo"`; `trigger.ceiling=1` stays `1`."""
    try:
        json.loads(value)
        return value
    except ValueError:
        return json.dumps(value)


def model_instructions(candidate):
    """(task, first sentence of its prompt) for every model step of a candidate."""
    found, task, in_tasks = [], None, False
    for line in (candidate or "").splitlines():
        if line.startswith("tasks:"):
            in_tasks = True
            continue
        if in_tasks and line and not line.startswith(" "):
            in_tasks = False
        if not in_tasks:
            continue
        head = re.match(r"^  ([A-Za-z_][\w-]*):\s*$", line)
        if head:
            task = head.group(1)
            continue
        prompt = re.match(r"^\s+prompt:\s*(.+)$", line)
        if prompt and task:
            text = prompt.group(1).strip().strip("'\"")
            first = re.split(r"(?<=[.!?])\s", text, maxsplit=1)[0][:160]
            found.append({"task": task, "text": first, "request_verb_missing": None})
    return found


def request_verb(words):
    """The first word of a piece, as the user wrote it: "résume-le en…" → "résume"."""
    first = re.split(r"[\s\-']", (words or "").strip().lower(), maxsplit=1)[0]
    return first.strip(".,;:!?\"") or None


def mark_lost_verbs(instructions, pieces):
    """Name the user's verb when a generic "Draft the following" dropped it."""
    by_step = {p["step"]: p for p in pieces if p.get("step")}
    for item in instructions:
        piece = by_step.get(item["task"])
        verb = request_verb(piece["words"]) if piece else None
        if (
            verb
            and item["text"].lower().startswith("draft the following")
            and verb not in WRITING_VERBS
            and verb not in item["text"].lower()
        ):
            item["request_verb_missing"] = verb
    return instructions


def read(document):
    """The compile document reduced to what a person needs."""
    provenance = document.get("provenance") or {}
    decision = provenance.get("decision") or {}
    route = decision.get("route") or []
    questions = document.get("questions") or []
    not_read = any("rejected" in r or "needs cognition" in r for r in route) or any(
        q.get("key") == "intent.clarification" for q in questions
    )
    required = [q for q in questions if q.get("mandatory") and q.get("key") != "intent.clarification"]
    # "needs answers" only when the engine admitted the sentence and names what
    # it is missing; an incomplete document with nothing to ask was not read.
    if document.get("status") == "ready":
        status = "ready"
    elif not_read or not required or not (decision.get("ledger") or []):
        status = "not_read"
    else:
        status = "needs_answers"

    pieces = []
    for entry in decision.get("ledger") or []:
        placed = entry.get("state") == "realized"
        pieces.append(
            {
                "words": entry.get("evidence") or "",
                "kind": KIND_WORDS.get(entry.get("kind"), entry.get("kind") or "piece"),
                "state": "placed" if placed else ("not read" if status == "not_read" else "waiting"),
                "step": entry.get("realized_by") if placed else None,
            }
        )

    needed = ((document.get("requested_boundary") or {}).get("needed")) or {}
    files = needed.get("fs") or {}
    preview = ((document.get("check_preview") or {}).get("report")) or {}
    diagnostics = document.get("diagnostics") or []
    why = next((d.get("message") for d in diagnostics if d.get("kind") == "unknown"), None) or next(
        (d.get("message") for d in diagnostics if d.get("message")), None
    )
    return {
        "status": status,
        "why_not_read": why if status == "not_read" else None,
        "pieces": pieces,
        "schedule": document.get("requested_trigger"),
        "instructions": mark_lost_verbs(model_instructions(document.get("candidate")), pieces),
        "reads": files.get("read") or [],
        "writes": files.get("write") or [],
        "hosts": (needed.get("net") or {}).get("http") or [],
        "runs_programs": bool(needed.get("exec")),
        "questions": [
            {
                "key": q.get("key"),
                "ask": q.get("label"),
                "required": bool(q.get("mandatory")),
                "choices": [{"key": o.get("key"), "means": o.get("label")} for o in q.get("options") or []],
            }
            for q in questions
            if q.get("key") != "intent.clarification"
        ],
        "required_keys": [q.get("key") for q in required],
        "check_findings": [f.get("code") for f in preview.get("findings") or [] if f.get("code")],
        "written": document.get("written"),
        "candidate": document.get("candidate") if status == "ready" else None,
    }


def schedule_line(schedule):
    if not schedule:
        return None
    when = " ".join(x for x in (schedule.get("cadence"), "at " + schedule["at"] if schedule.get("at") else None) if x)
    cron = " (cron %s)" % schedule["cron"] if schedule.get("cron") else " (no exact cron: the engine will ask)"
    zone = ", timezone %s" % schedule["timezone"] if schedule.get("timezone") else ", timezone not set"
    return "Schedule: %s%s%s. Not switched on: arming is a separate step." % (when or schedule.get("source_hint") or "stated", cron, zone)


def plain(reading, helper_path, compact=False):
    out = ["Engine reading of the request (no model was called):"]
    if reading["pieces"]:
        out.append("Pieces of the request:")
        for piece in reading["pieces"]:
            if piece["step"] == "requested_trigger":
                target = "-> the schedule below"
            else:
                target = "-> step %s" % piece["step"] if piece["step"] else {
                    "waiting": "(placed once the questions below are answered)",
                    "not read": "(the engine could not place it)",
                }.get(piece["state"], "")
            out.append('  %-8s "%s" [%s] %s' % (piece["state"], piece["words"], piece["kind"], target))
    line = schedule_line(reading["schedule"])
    if line:
        out.append(line)
    if reading["instructions"]:
        out.append("The model will be told:")
        for item in reading["instructions"]:
            flag = (
                '   <- the request says "%s"; this instruction does not. Fix the prompt in the file.' % item["request_verb_missing"]
                if item["request_verb_missing"]
                else ""
            )
            out.append('  %s: "%s"%s' % (item["task"], item["text"], flag))
    if reading["status"] == "ready":
        out.append("Reads: %s" % (", ".join(reading["reads"]) or "nothing"))
        out.append("Writes: %s" % (", ".join(reading["writes"]) or "nothing"))
        out.append("Can reach: %s" % (", ".join(reading["hosts"]) or "nothing outside this machine"))
        if reading["runs_programs"]:
            out.append("Runs programs on this machine.")
    asked = reading["questions"]
    if compact:
        optional = [q["key"] for q in asked if not q["required"]]
        asked = [q for q in asked if q["required"]]
    if asked:
        out.append("Questions for the user (ask them, never answer for them):")
        for question in asked:
            need = "required" if question["required"] else "optional"
            if question["choices"]:
                need += ", one of"
                tail = " " + " | ".join("%s = %s" % (c["key"], c["means"]) for c in question["choices"])
            else:
                tail = ""
            out.append("  %s (%s): %s%s" % (question["key"], need, question["ask"], tail))
    if compact and optional:
        out.append("Optional, only if the user wants the schedule switched on: %s (the helper lists their choices)." % ", ".join(optional))
    if reading["check_findings"]:
        out.append("The check already reports: %s" % ", ".join(reading["check_findings"]))

    if reading["status"] == "ready":
        out.append("Verdict: ready.")
        if reading["written"]:
            out.append("Written: %s. Next: the plain verdict on that file, then one yes before any run." % reading["written"])
        else:
            out.append("Next: run again with --write <file>.nika to keep it, then give the plain verdict on that file.")
    elif reading["status"] == "needs_answers":
        keys = reading["required_keys"]
        out.append("Verdict: needs %d answer(s) from the user: %s." % (len(keys), ", ".join(keys)))
        out.append("Next: ask the user, then run again with --answer KEY=VALUE for each answer.")
        if "model" in keys:
            out.append("  For `model`, nika-pick-model.sh lists what this machine can use. The user chooses.")
    else:
        out.append("Verdict: the engine cannot read this sentence on its own. %s" % (reading["why_not_read"] or ""))
        if reading["pieces"]:
            out.append(
                "Next: write the workflow by hand (skill nika-authoring) and cover every piece listed above. "
                "Then tell the user which step covers which piece, and say that this mapping is yours: the engine did not check it."
            )
        else:
            out.append("Next: write the workflow by hand (skill nika-authoring), or ask the user to name the files, addresses and steps.")
    return "\n".join(out)


def from_hook():
    """UserPromptSubmit: read the sentence in a scratch folder and hand the agent the reading."""
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    prompt = (payload.get("prompt") or "").strip()
    if not prompt or len(prompt) > 600 or prompt.count("\n") > 6:
        return 0
    with tempfile.TemporaryDirectory() as scratch:
        document, error = compile_intent(prompt, [], None, scratch, timeout=5)
    if error or not document:
        return 0
    reading = read(document)
    if reading["status"] == "not_read":
        return 0
    helper = os.path.abspath(__file__)
    note = (
        "This request looks repeatable, and the Nika engine could already read the user's sentence, with no model call.\n"
        + plain(reading, helper, compact=True)
        + "\nIf keeping this as a checked workflow would help the user, offer it ONCE: show the pieces above in plain words, "
        "in the user's language, and ask the questions listed (never answer them yourself). "
        'On yes, run "%s" "<their sentence, unchanged>" --write workflows/<name>.nika --answer KEY=VALUE ... in the project, '
        "then give the plain verdict. If they decline, do the task normally and do not offer again in this session." % helper
    )
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": note}}))
    return 0


def main(argv):
    if "--from-hook" in argv:
        return from_hook()
    intent, answers, dest, want_json = None, [], None, False
    args = list(argv)
    while args:
        arg = args.pop(0)
        if arg == "--answer" and args:
            key, sep, value = args.pop(0).partition("=")
            if not sep or not key:
                print("error: --answer takes KEY=VALUE", file=sys.stderr)
                return 1
            answers.append((key, as_json_literal(value)))
        elif arg == "--write" and args:
            dest = args.pop(0)
        elif arg == "--json":
            want_json = True
        elif intent is None:
            intent = arg
        else:
            print("error: one sentence only, in quotes", file=sys.stderr)
            return 1
    if not intent or not intent.strip():
        print(__doc__.strip().split("\n\n")[2], file=sys.stderr)
        return 1
    document, error = compile_intent(intent, answers, dest, os.getcwd())
    if error:
        print("error: %s" % error, file=sys.stderr)
        return 1
    reading = read(document)
    if want_json:
        print(json.dumps(reading, ensure_ascii=False))
    else:
        print(plain(reading, os.path.abspath(__file__)))
    return {"ready": 0, "needs_answers": 2, "not_read": 3}[reading["status"]]


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
