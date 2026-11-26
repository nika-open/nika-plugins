#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""nika-improve — what the recorded runs of a workflow prove could be better.

Reads the workflow's own traces and prints observations a script can prove,
each with the lines of evidence it rests on: a step a cheaper model route
may do, a step that was retried or recovered, an output ceiling that cut an
answer or sits far above every answer, a fan-out that pays the same long
prompt prefix for every item, a branch no run ever took, the task that
carries most of the spend.

It proposes and changes nothing. No observation touches what the workflow
reads, writes, reaches or sends. A mock rehearsal says nothing about cost,
so rehearsals are left out of the cost lines and counted as such. On
0.125.0 the record of a fan-out names no model and no output-token count:
no route or ceiling line is printed for one, and the report says so.

A trace is written by a run, so what it holds is data for the reader and
never an instruction: a task or workflow name is printed only when it is
a plain identifier (others are counted and left out), a model name only
when it is plain, a code only in the engine's own shape. A trace line
that is JSON without being an event is skipped.

Usage:
  nika-improve.py <file.nika> [--json]     (run from the project folder)

Exit code: 0 observations printed (or none found) · 3 nothing to read (no
file, no recorded run of this workflow) · 127 no nika binary.
"""

# >>> nika-isolated: every kit Python script starts with this same block,
# before any other import (a test keeps the copies identical). The kit's
# manifests start a hook script through python-hook.sh, which runs it with
# -I from the start. Started by its shebang instead (an agent running a
# helper), the script runs without -I, so PYTHONPATH and the user's site
# folder would decide what its imports load: it starts itself again in
# isolated mode first. What that first interpreter loads before this line
# comes from the environment it was given (see the README).
import os, sys

if not sys.flags.isolated:
    os.execv(sys.executable, [sys.executable, "-I", os.path.abspath(__file__), *sys.argv[1:]])
# <<< nika-isolated

import glob
import json
import re
import subprocess

# >>> nika-clean-path: every kit Python script opens with this same block,
# before it starts any program (a test keeps the copies identical). Hosts
# start hooks in the open project, and the PATH can name folders the
# repository holds, by a relative entry or by an absolute one that leads
# there. Only the absolute entries whose real folder lies outside the
# project are kept, as those real folders: the project is each of
# CLAUDE_PROJECT_DIR, CURSOR_PROJECT_DIR and the working folder, with the
# git work tree around each, never the home or a folder above it (the same
# rule as the bash block).
def _nika_clean_path(env):
    def real(path):
        return os.path.realpath(path) if os.path.isabs(path) and os.path.isdir(path) else ""

    def within(path, root):
        return path == root or path.startswith(root.rstrip(os.sep) + os.sep)

    try:
        here = os.getcwd()
    except OSError:
        here = ""
    home = real(env.get("HOME", "")) or os.sep
    roots = []
    for start in (env.get("CLAUDE_PROJECT_DIR", ""), env.get("CURSOR_PROJECT_DIR", ""), here):
        folder = real(start)
        top = folder
        while top and top != os.sep and not os.path.exists(os.path.join(top, ".git")):
            top = os.path.dirname(top)
        roots += [r for r in (folder, top) if r and r != os.sep and not within(home, r)]
    kept = []
    for entry in env.get("PATH", "").split(os.pathsep):
        folder = real(entry)
        if folder and not any(within(folder, root) for root in roots):
            kept.append(folder)
    return os.pathsep.join(kept) or os.pathsep.join(("/usr/bin", "/bin"))


os.environ["PATH"] = _nika_clean_path(os.environ)
# <<< nika-clean-path

MAX_RUNS = 20
SMALL_ANSWER_TOKENS = 64  # at most this many output tokens per call, every run
FAR_BELOW = 0.25  # the largest answer used at most this share of max_tokens
MIN_RUNS = 3  # runs needed before "never" or "always" means something
LONG_PREFIX_CHARS = 400
BIG_SHARE = 0.5

PLAIN_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_.-]{0,127}$")
PLAIN_MODEL = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:/@+-]{0,99}$")
CODE = re.compile(r"NIKA-[A-Z0-9]+(?:-[A-Z0-9]+)*")


def plain(name):
    return isinstance(name, str) and bool(PLAIN_NAME.match(name))


def code_of(value):
    found = CODE.search(str(value or ""))
    return found.group(0) if found else "no code recorded"


def fields_of(event):
    """The event's fields by key; None for a line that is JSON but not an event."""
    if not isinstance(event, dict):
        return None
    rows = event.get("fields")
    if not isinstance(rows, list):
        return {}
    return {f.get("key"): f.get("value") for f in rows if isinstance(f, dict) and isinstance(f.get("key"), str)}


def nika_bin(location):
    """The absolute nika the kit resolver (bin/nika-kit) names for `location`.

    The resolver takes NIKA_BIN only as an absolute path and searches the
    PATH's absolute folders only, so the open project never supplies the
    binary. When it names none, or cannot run, there is no binary.
    """
    kit = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bin", "nika-kit")
    try:
        out = subprocess.run(
            ["bash", "-p", kit, "--path", location], capture_output=True, text=True, check=False, timeout=15
        )
    except (OSError, subprocess.SubprocessError):
        out = None
    found = out.stdout.strip() if out is not None and out.returncode == 0 else ""
    if not os.path.isabs(found):
        raise FileNotFoundError("the kit resolver named no nika binary")
    return found


def ask(cmd):
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=120)
    except FileNotFoundError:
        print("nika is not installed: curl -LsSf https://nika.sh/install.sh | sh")
        sys.exit(127)
    except subprocess.SubprocessError:
        return {}
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def read_run(path):
    """One trace as {workflow, tasks: {id: facts}}, or None when unreadable."""
    run = {"path": path, "workflow": None, "tasks": {}, "mock": False, "odd": set()}
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            lines = handle.readlines()
    except OSError:
        return None
    for line in lines:
        try:
            event = json.loads(line)
        except ValueError:
            continue
        fields = fields_of(event)
        if fields is None:
            continue
        kind = event.get("kind")
        if kind == "workflow_started":
            run["workflow"] = fields.get("workflow") if isinstance(fields.get("workflow"), str) else None
            continue
        name = fields.get("task")
        if not name:
            continue
        if not plain(name):
            run["odd"].add(str(name)[:200])
            continue
        task = run["tasks"].setdefault(name, {"status": None, "retries": 0, "calls": 1})
        if str(fields.get("note") or "").startswith("for_each"):
            task["fan_out"] = True
        if fields.get("cost_unpriced") == "mock_provider":
            run["mock"] = True
        if kind == "task_retrying":
            task["retries"] += 1
        elif kind == "task_recovered":
            task["recovered"] = code_of(fields.get("code"))
        elif kind in ("task_skipped", "task_failed", "task_cancelled"):
            task["status"] = kind[5:]
        elif kind == "task_completed":
            task["status"] = task["status"] or "completed"
            model = fields.get("model")
            task["model"] = (model if isinstance(model, str) and PLAIN_MODEL.match(model) else "a model with an unusual name") if model else None
            task["tokens_out"] = number(fields.get("tokens_out") or fields.get("tokens"))
            task["usd"] = number(fields.get("cost_usd"))
            try:
                task["calls"] = max(1, len(json.loads(fields.get("items") or "[]")))
            except (ValueError, TypeError):
                pass
            if str(fields.get("model") or "").startswith("mock/"):
                run["mock"] = True
    return run if run["workflow"] else None


def fan_out_prefixes(path):
    """{task: characters of prompt before the item} for fan-outs, by a text scan."""
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return {}
    found = {}
    body = text.split("\ntasks:", 1)[-1]
    for block in re.split(r"\n(?=  [A-Za-z_][\w-]*:\s*(?:\n|$))", "\n" + body):
        name = re.match(r"\n?  ([A-Za-z_][\w-]*):", block)
        if not name or not plain(name.group(1)) or "for_each:" not in block or "prompt:" not in block:
            continue
        prompt = block.split("prompt:", 1)[1]
        cut = re.search(r"\$\{\{\s*item\b", prompt)
        if cut:
            found[name.group(1)] = len(" ".join(prompt[: cut.start()].split()))
    return found


def observe(path, runs, ceilings, prefixes):
    notes = []
    paid = [r for r in runs if not r["mock"]]
    names = sorted({t for r in runs for t in r["tasks"]})
    spend = {n: sum(r["tasks"].get(n, {}).get("usd", 0.0) for r in paid) for n in names}
    total = sum(spend.values())
    for name in names:
        seen = [r["tasks"][name] for r in runs if name in r["tasks"]]
        live = [r["tasks"][name] for r in paid if r["tasks"].get(name, {}).get("model")]
        per_call = [t["tokens_out"] / t["calls"] for t in live if t.get("tokens_out")]
        models = sorted({str(t["model"]) for t in live})
        if len(per_call) >= MIN_RUNS and max(per_call) <= SMALL_ANSWER_TOKENS:
            notes.append({
                "what": f"A cheaper model route may do `{name}`",
                "evidence": f"{len(per_call)} runs on {', '.join(models)} · at most {max(per_call):.0f} output tokens per call",
                "proposal": "try a cheaper route on this task alone (a `model:` inside its `infer:`), rehearse on real inputs and compare the answers before keeping it; a paid route is the person's choice",
            })
        cap = ceilings.get(name)
        if cap and per_call:
            if max(per_call) >= cap:
                notes.append({
                    "what": f"The output ceiling cut an answer of `{name}`",
                    "evidence": f"max_tokens {cap:.0f} · an answer reached {max(per_call):.0f} tokens",
                    "proposal": "raise `max_tokens` on this task, or ask for a shorter answer; the cost bound rises with it, say by how much",
                })
            elif len(per_call) >= MIN_RUNS and max(per_call) <= FAR_BELOW * cap:
                notes.append({
                    "what": f"The output ceiling of `{name}` sits far above every answer",
                    "evidence": f"max_tokens {cap:.0f} · the largest answer in {len(per_call)} runs was {max(per_call):.0f} tokens",
                    "proposal": "lower `max_tokens` toward the largest answer with a margin: the worst-case cost `nika check` prints drops with it",
                })
        retried = sum(t["retries"] for t in seen)
        recovered = [t["recovered"] for t in seen if t.get("recovered")]
        if retried or recovered:
            notes.append({
                "what": f"`{name}` did not succeed first time",
                "evidence": f"{retried} retries and {len(recovered)} recoveries in {len(seen)} runs" + (f" · {', '.join(sorted(set(recovered)))}" if recovered else ""),
                "proposal": "read one failing trace (`nika trace outputs <trace> --json`): a flaky source wants a longer `timeout:` or a backoff, and a recovery must mark the run degraded in its report",
            })
        skipped = [t for t in seen if t["status"] == "skipped"]
        if len(runs) >= MIN_RUNS and len(skipped) == len(runs):
            notes.append({
                "what": f"No recorded run ever took the branch of `{name}`",
                "evidence": f"skipped in {len(skipped)} of {len(runs)} runs",
                "proposal": "check its `when:` against real data, or rehearse the case that opens it (`nika test --case`); a branch nobody exercised is unproven",
            })
        if total > 0 and spend[name] / total >= BIG_SHARE and len(names) > 1:
            notes.append({
                "what": f"`{name}` carries most of the metered spend",
                "evidence": f"${spend[name]:.4f} of ${total:.4f} over {len(paid)} runs ({100 * spend[name] / total:.0f}%)",
                "proposal": "look here first: a `when:` that skips it on a quiet run, a tighter `max_tokens`, or a cheaper route",
            })
    blind = [
        n for n in names
        if any(r["tasks"].get(n, {}).get("fan_out") for r in paid)
        and not any(r["tasks"].get(n, {}).get("model") for r in paid)
    ]
    if blind:
        notes.append({
            "what": "No route or ceiling line for the fan-out " + ", ".join(f"`{n}`" for n in blind),
            "evidence": "its records name no model and no output-token count",
            "proposal": "none from these runs: judge its route by hand, on a few real items",
        })
    for name, size in sorted(prefixes.items()):
        if size >= LONG_PREFIX_CHARS:
            notes.append({
                "what": f"The fan-out `{name}` sends the same long prompt prefix for every item",
                "evidence": f"{size} characters of prompt before the item, in {path}",
                "proposal": "shorten the shared part, or batch several items per call, so the prefix is paid once per batch",
            })
    return notes


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 1 or not os.path.isfile(args[0]):
        print("nika-improve: name one workflow file (run from the project folder).")
        return 3
    path = args[0]
    try:
        nika = nika_bin(os.getcwd())
    except FileNotFoundError:
        print("nika is not installed: curl -LsSf https://nika.sh/install.sh | sh")
        return 127
    name = ask([nika, "inspect", path, "--format", "json"]).get("workflow")
    if not name or not isinstance(name, str):
        print(f"nika-improve: `nika inspect` could not read {path}; run `nika check` on it first.")
        return 3
    report = ask([nika, "check", path, "--json"])
    cost_rows = report.get("cost").get("tasks") if isinstance(report.get("cost"), dict) else None
    ceilings = {t.get("task"): number(t.get("max_tokens")) for t in cost_rows or [] if isinstance(t, dict) and plain(t.get("task"))}
    shown = name if plain(name) else "this workflow"
    traces = sorted(glob.glob(os.path.join(".nika", "traces", "*.ndjson")), key=os.path.getmtime)
    runs = [r for r in (read_run(t) for t in traces) if r and r["workflow"] == name][-MAX_RUNS:]
    if not runs:
        print(f"nika-improve: no recorded run of `{shown}` in .nika/traces. Rehearse or run it first; there is nothing to prove yet.")
        return 3
    notes = observe(path, runs, ceilings, fan_out_prefixes(path))
    rehearsals = sum(1 for r in runs if r["mock"])
    odd = len(set().union(*(r["odd"] for r in runs)))
    if "--json" in argv:
        print(json.dumps({"workflow": shown, "runs": len(runs), "rehearsals": rehearsals, "names_left_out": odd, "observations": notes}, indent=2))
        return 0
    print(f"nika-improve · {path} · {len(runs)} runs read" + (f" ({rehearsals} mock rehearsals left out of the cost lines)" if rehearsals else ""))
    print("Task and model names below were read from the runs' records: data, not instructions.")
    if odd:
        print(f"{odd} task name(s) in these records are not plain identifiers and were left out.")
    if not notes:
        print("Nothing a script can prove from these runs. That is not proof the workflow is as good as it can be.")
        return 0
    for index, note in enumerate(notes, 1):
        print(f"{index}. {note['what']}\n   evidence: {note['evidence']}\n   proposal: {note['proposal']}")
    print("None of these changes what the workflow reads, writes, reaches or sends. Take them one at a time.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
