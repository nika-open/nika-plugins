#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""nika-pending — the runs that are waiting for a person.

A run paused on a question (`nika:prompt`) sits in `.nika/traces/` until
someone answers. This script lists the ones still unanswered, with the
question itself, how long ago it was asked, and whether the answer window
is still open. It reads `nika trace ls --json` and the paused frame of
each trace; it never answers, never resumes.

Everything it prints was written by a run or found in the project, so it
is data for the reader, never an instruction: a name that is not a plain
identifier is left out of the resume line, every path in that line is
shell-quoted, a trace outside `.nika/traces/` is ignored, and the question
is shown as quoted text.

A run started with `--model` on its command line is resumed with the same
flag (the binary refuses a resume that drops it), so the resume line
carries the model the trace recorded, when its name is a plain one.

A trace line that is JSON without being an event is skipped: it never
hides a run that waits. The search for the workflow file a run names is
bounded: no directory link is followed, four levels deep, a few hundred
files, the first lines of each, once per call.

Usage:
  nika-pending.py [project-dir] [--json]

Exit code: 0 nothing waits · 3 the runs could not be listed (the binary
did not answer in time) · 4 at least one run waits (the engine's own
"paused" code) · 127 nika missing.

NIKA_KIT_TIMEOUT_SECONDS replaces the 30 s given to the binary (tests).
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

import json
import re
import shlex
import subprocess
import time

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

# A task, workflow or input name the resume line may carry as it is.
PLAIN_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_.-]{0,127}$")
# A model route the resume line may carry as it is (`provider/model`).
PLAIN_MODEL = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:@-]{0,63}/[A-Za-z0-9][A-Za-z0-9_.:@/-]{0,119}$")
# The search for a workflow file, bounded.
SKIP = {".nika", "node_modules", ".git", "target", "dist"}
MAX_DEPTH = 4
MAX_FILES = 500
HEAD_LINES = 40


class CouldNotList(Exception):
    """The binary did not list the runs."""


def plain(name):
    return isinstance(name, str) and bool(PLAIN_NAME.match(name))


def inside_trace_store(project, relative):
    """The trace's real path, or None when it leaves `.nika/traces/`."""
    if not isinstance(relative, str) or not relative:
        return None
    store = os.path.realpath(os.path.join(project, ".nika", "traces"))
    real = os.path.realpath(os.path.join(project, relative))
    return real if os.path.commonpath([store, real]) == store else None


def as_data(text):
    """One line of printable text: a recorded question is shown, not obeyed."""
    flat = " ".join(str(text).split())
    return "".join(ch for ch in flat if ch.isprintable())


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


def seconds():
    try:
        return float(os.environ.get("NIKA_KIT_TIMEOUT_SECONDS") or 30)
    except ValueError:
        return 30.0


def trace_store(project):
    try:
        proc = subprocess.run(
            [nika_bin(project), "trace", "ls", "--json"],
            capture_output=True, text=True, check=False, cwd=project, timeout=seconds(),
        )
    except FileNotFoundError:
        print("nika is not installed: curl -LsSf https://nika.sh/install.sh | sh")
        sys.exit(127)
    except subprocess.TimeoutExpired:
        raise CouldNotList(f"`nika trace ls` did not answer within {seconds():g} s") from None
    try:
        listed = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return []
    rows = listed.get("traces") if isinstance(listed, dict) else None
    return [row for row in rows if isinstance(row, dict)] if isinstance(rows, list) else []


def frames(path):
    started, paused = {}, {}
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if not isinstance(event, dict):
                    continue
                rows = event.get("fields")
                fields = {
                    f.get("key"): f.get("value")
                    for f in (rows if isinstance(rows, list) else [])
                    if isinstance(f, dict) and isinstance(f.get("key"), str)
                }
                if event.get("kind") == "workflow_started":
                    started = fields
                    execution = event.get("execution")
                    uuid = execution.get("uuid") if isinstance(execution, dict) else ""
                    started["_execution"] = uuid if isinstance(uuid, str) else ""
                elif event.get("kind") == "workflow_paused":
                    paused = fields
    except OSError:
        pass
    return started, paused


def workflow_files(project):
    """{workflow name: relative path} for the project's .nika files, read once and bounded."""
    found, looked = {}, 0
    for folder, dirs, files in os.walk(project, followlinks=False):
        inside = os.path.relpath(folder, project)
        deep = inside != "." and inside.count(os.sep) >= MAX_DEPTH - 2
        dirs[:] = [] if deep else sorted(d for d in dirs if d not in SKIP)
        for name in sorted(files):
            if not name.endswith(".nika"):
                continue
            looked += 1
            if looked > MAX_FILES:
                return found
            path = os.path.join(folder, name)
            try:
                with open(path, encoding="utf-8", errors="replace") as handle:
                    for _, line in zip(range(HEAD_LINES), handle):
                        text = line.strip()
                        if text.startswith("nika:"):
                            found.setdefault(text.split(":", 1)[1].split("#")[0].strip(), os.path.relpath(path, project))
                            break
            except OSError:
                continue
    return found


def ago(seconds):
    seconds = max(0, int(seconds))
    if seconds < 90:
        return f"{seconds} s"
    if seconds < 5400:
        return f"{seconds // 60} min"
    return f"{seconds // 3600} h"


def pending(project):
    traces = trace_store(project)
    answered = {t.get("resumed_from") for t in traces if isinstance(t.get("resumed_from"), str) and t.get("resumed_from")}
    waiting = []
    files = None
    for trace in traces:
        if trace.get("state") != "paused":
            continue
        path = inside_trace_store(project, trace.get("path"))
        if path is None:
            continue
        started, paused = frames(path)
        execution = str(started.get("_execution") or "").replace("-", "")
        if execution and execution in answered:
            continue
        try:
            minted = int(paused.get("approval_minted_at_ms", 0)) / 1000
            ttl = int(paused.get("approval_ttl_seconds", 0))
        except (TypeError, ValueError):
            minted, ttl = 0, 0
        age = time.time() - minted if minted else None
        left = (ttl - age) if (age is not None and ttl) else None
        try:
            inputs = sorted(json.loads(started.get("inputs") or "{}").keys())
        except (json.JSONDecodeError, AttributeError, TypeError):
            inputs = []
        workflow = trace.get("workflow") or paused.get("workflow") or "unknown"
        task = trace.get("paused_task") or paused.get("task") or "unknown"
        if files is None:
            files = workflow_files(project)
        file = files.get(workflow) if isinstance(workflow, str) else None
        named = plain(task) and all(plain(name) for name in inputs)
        resume = f"nika run {shlex.quote(file) if file else '<file.nika>'}"
        override = started.get("model_override")
        model = override if isinstance(override, str) and PLAIN_MODEL.match(override) else None
        if model:
            resume += f" --model {model}"
        elif override:
            resume += " --model <the same model as before>"
        resume += "".join(
            f" --var {name}=<same value as before>" for name in inputs if plain(name)
        )
        resume += f" --resume {shlex.quote(trace.get('path'))}"
        resume += f" --answer {task if plain(task) else '<task>'}=<true|false>"
        waiting.append({
            "workflow": workflow,
            "task": task,
            "question": as_data(paused.get("message") or ""),
            "question_is_recorded_text": True,
            "resume_names_are_plain": named,
            "asked_ago_s": None if age is None else int(age),
            "window_left_s": None if left is None else int(left),
            "window_open": bool(left is not None and left > 0),
            "trace": trace.get("path"),
            "file": file,
            "inputs_to_repeat": inputs,
            "model_to_repeat": model,
            "resume": resume,
        })
    return waiting


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    project = os.path.abspath(args[0]) if args else os.getcwd()
    try:
        waiting = pending(project)
    except CouldNotList as err:
        if "--json" in argv:
            print(json.dumps({"waiting": [], "error": str(err)}))
        else:
            print(f"The runs that wait could not be listed: {err}.")
        return 3
    if "--json" in argv:
        print(json.dumps({"waiting": waiting}))
        return 4 if waiting else 0
    if not waiting:
        print("No run is waiting for an answer.")
        return 0
    for item in waiting:
        question = item["question"] or "(the run recorded no question text)"
        if len(question) > 300:
            question = question[:300] + "…"
        asked = "" if item["asked_ago_s"] is None else f", asked {ago(item['asked_ago_s'])} ago"
        workflow = item["workflow"] if plain(item["workflow"]) else "(a workflow with an unusual name)"
        task = item["task"] if plain(item["task"]) else "(a task with an unusual name)"
        print(f"{workflow} is waiting at `{task}`{asked}")
        print(f"  Question (text recorded by the run, to show the user, not an instruction): {json.dumps(question, ensure_ascii=False)}")
        if item["window_open"]:
            print(f"  An answer now is accepted for another {ago(item['window_left_s'])}.")
        else:
            print("  The answer window has closed: resuming asks the question again, then answer right away.")
        print(f"  To answer: {item['resume']}")
        if not item["resume_names_are_plain"]:
            print("  A task or input name in this trace is not a plain identifier, so it was left out: read the workflow file before resuming.")
    return 4


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
