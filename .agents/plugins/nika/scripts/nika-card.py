#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""nika-card — what a workflow touches, how deep it is, what a run costs.

One page for the plan gate, the reviewer and the hand-over. Every line is
read off `nika check --json --native-strict` and `nika inspect --format
json`; nothing is judged by reading the YAML. Where the binary does not say
(it names a host, not whether a call there reads or sends), the card says
so instead of guessing.

One more `nika check`, asked with `--model mock/echo`, names the models a
run on the mock model would still call. The mock replaces the workflow's
own model and nothing else: a model a task pins is called for real, and
billed, under a mock run. The card says so in words, since a job like that
is read with `--dry-run` and never rehearsed on the mock model.

Usage:
  nika-card.py <file.nika> [--json]
  nika-card.py <file.nika> --plan         also remember these effects as the
                                          plan the person approved
  nika-card.py <file.nika> --since-plan   also list every effect the file
                                          has now and the plan did not

The remembered plan lives outside the project (the plugin's data folder,
else the temporary folder), keyed by the file's path. Recording a plan
again replaces it, and the card then says so and lists the effects the
earlier plan did not have. `--since-plan` catches an effect added by
mistake between the plan and the hand-over. It cannot hold an agent that
records a new plan: the approval itself is the person's, given in the
conversation, and no file stands in for it.

Exit code: 0 card printed and the check is clean · 2 card printed, the
check refuses the file · 3 no card (no file, unreadable output) · 4 clean,
and an effect was added since the plan · 127 no nika binary.
"""
import hashlib
import json
import os
import subprocess
import sys

REVIEW_ABOVE_TASKS = 8
TIERS = (
    ("reads", "reads"),
    ("writes_in_project", "writes in the project"),
    ("leaves_the_machine", "leaves the machine"),
    ("spends", "spends"),
    ("unpriced_models", "unpriced model"),
    ("called_on_mock", "called even on a mock run"),
    ("runs_programs", "runs a program"),
)


def nika_bin(location):
    """The binary the kit resolved (bin/nika-kit), else NIKA_BIN, else PATH."""
    kit = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bin", "nika-kit")
    if os.access(kit, os.X_OK):
        try:
            out = subprocess.run(
                [kit, "--path", location], capture_output=True, text=True, check=False, timeout=15
            )
            if out.returncode == 0 and out.stdout.strip():
                return out.stdout.strip()
        except (OSError, subprocess.SubprocessError):
            pass
    return os.environ.get("NIKA_BIN") or "nika"


def call(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=120)
    except FileNotFoundError:
        print("nika is not installed: curl -LsSf https://nika.sh/install.sh | sh")
        sys.exit(127)
    except subprocess.SubprocessError as err:
        print(f"nika did not answer: {err}")
        sys.exit(3)


def as_json(proc, what):
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        tail = (proc.stderr or proc.stdout).strip().splitlines()[-1:] or ["no output"]
        print(f"No card: {what} printed no JSON ({tail[0][:200]})")
        sys.exit(3)
    if not isinstance(data, dict):
        print(f"No card: {what} printed JSON of an unknown shape")
        sys.exit(3)
    return data


def in_project(path):
    path = str(path)
    if path.startswith(("/", "~")):
        return False
    return not os.path.normpath(path).startswith("..")


def effects(report):
    """The five effect rows, each a list of evidence strings (empty = no)."""
    needed = (report.get("permits") or {}).get("needed") or {}
    fs = needed.get("fs") or {}
    journey = report.get("data_journey") or {}
    writes = [str(w) for w in fs.get("write") or []]
    hosts = [str(h) for h in (needed.get("net") or {}).get("http") or []]
    tools = [str(t) for t in needed.get("tools") or []]
    programs = needed.get("exec") or []
    programs = [str(p) for p in programs] if isinstance(programs, list) else []
    out = [f"host {h}" for h in hosts]
    out += [f"write outside the project {w}" for w in writes if not in_project(w)]
    out += [f"tool {t}" for t in tools if t.startswith("mcp:") or t == "nika:notify"]
    paid = []
    unpriced = []
    for end in journey.get("model_endpoints") or []:
        label = f"{end.get('model')} ({end.get('task')})"
        (paid if end.get("priced") else unpriced).append(label)
    return {
        "reads": [str(r) for r in fs.get("read") or []],
        "writes_in_project": [w for w in writes if in_project(w)],
        "leaves_the_machine": out,
        "spends": paid,
        "unpriced_models": unpriced,
        "runs_programs": programs,
    }


def called_on_mock(proc):
    """Models a run on the mock model would still call, or None when the binary did not say."""
    try:
        ends = (json.loads(proc.stdout).get("data_journey") or {}).get("model_endpoints")
    except (ValueError, AttributeError):
        return None
    if not isinstance(ends, list):
        return None
    return [
        f"{end.get('model')} ({end.get('task')})"
        for end in ends
        if isinstance(end, dict) and not str(end.get("model") or "").startswith("mock/")
    ]


def depth(graph, report):
    nodes = [n for n in graph.get("nodes") or [] if isinstance(n, dict)]
    edges = [e for e in graph.get("edges") or [] if isinstance(e, dict)]
    tasks = [n for n in nodes if n.get("kind", "task") == "task"]
    builtins = sorted({n["tool"] for n in tasks if str(n.get("tool") or "").startswith("nika:")})
    incoming = {}
    for edge in edges:
        incoming.setdefault(edge.get("to"), set()).add(edge.get("from"))
    routes = [e for e in edges if e.get("predicate") in ("failure", "terminal", "unwind")]
    journey = report.get("data_journey") or {}
    read = {s.get("target") for s in journey.get("sources") or [] if s.get("kind") == "fs.read"}
    state = sorted(str(p) for p in read & set(journey.get("writes") or []))
    return {
        "tasks": len(tasks),
        "builtins": builtins,
        "when": [n.get("id") for n in tasks if n.get("when")],
        "failure_routes": sorted({str(e.get("to")) for e in routes}),
        "joins": sorted(str(k) for k, v in incoming.items() if len(v) > 1),
        "fan_outs": [n.get("id") for n in tasks if n.get("fan_out")],
        "gates": [n.get("id") for n in tasks if n.get("tool") == "nika:prompt"],
        "state_paths": state,
    }


def verdict(report):
    rows = []
    for finding in report.get("findings") or []:
        rows.append(f"{finding.get('code')}: {str(finding.get('message') or '')[:160]}")
    for blocker in (report.get("verdicts") or {}).get("blockers") or []:
        rows.append(f"blocker: {str(blocker)[:200]}")
    return {
        "clean": bool(report.get("clean")),
        "native_strict_clean": bool(report.get("native_strict_clean")),
        "paid_ready": bool(report.get("paid_ready")),
        "problems": rows,
        "hints": [f"{h.get('kind')} ({h.get('task')})" for h in report.get("hints") or []],
    }


def cost(report, text):
    data = report.get("cost") or {}
    printed = [ln.strip() for ln in text.splitlines() if " COST " in f" {ln} "]
    open_ended = [
        f"{t.get('task')} ({t.get('unbounded_reason')})"
        for t in data.get("tasks") or []
        if t.get("unbounded_reason")
    ]
    return {
        "printed": printed[0] if printed else None,
        "bounded_total_usd": data.get("bounded_total_usd"),
        "unbounded": open_ended,
    }


def review(card):
    reasons = []
    if card["depth"]["tasks"] > REVIEW_ABOVE_TASKS:
        reasons.append(f"{card['depth']['tasks']} tasks")
    if card["effects"]["leaves_the_machine"]:
        reasons.append("an effect leaves the machine")
    if card["effects"]["runs_programs"]:
        reasons.append("it runs a program")
    return reasons


def plan_path(path):
    store = os.environ.get("CLAUDE_PLUGIN_DATA") or os.environ.get("TMPDIR") or "/tmp"
    key = hashlib.sha256(os.path.abspath(path).encode()).hexdigest()[:16]
    return os.path.join(store, f"nika-plan-{key}.json")


def added_since_plan(path, now):
    """Effects in `now` that the remembered plan lacks, or None with no plan."""
    try:
        with open(plan_path(path), encoding="utf-8") as handle:
            plan = json.load(handle)
    except (OSError, ValueError):
        return None
    added = []
    for tier, label in TIERS:
        before = set(plan.get(tier) or [])
        added += [f"{label}: {item}" for item in now.get(tier) or [] if item not in before]
    return added


def row(label, items, empty="no"):
    return f"  {label:<22}{', '.join(str(i) for i in items) if items else empty}"


def render(card):
    eff, dep, ver = card["effects"], card["depth"], card["verdict"]
    state = "clean" if ver["clean"] else "NOT clean"
    lines = [f"nika-card · {card['file']} · {card['workflow']}"]
    lines.append(f"Verdict   {state} · paid ready: {'yes' if ver['paid_ready'] else 'no'}")
    lines += [f"  {p}" for p in ver["problems"]]
    if ver["hints"]:
        lines.append("  hints: " + ", ".join(ver["hints"]))
    lines.append("Effects   (permits needed and data journey, from nika check)")
    only_reads = not (eff["writes_in_project"] or eff["leaves_the_machine"] or eff["runs_programs"])
    lines.append(row("reads only", ["yes"] if only_reads and not eff["spends"] else []))
    lines.append(row("reads", eff["reads"], "nothing on disk"))
    lines.append(row("writes in the project", eff["writes_in_project"]))
    lines.append(row("leaves the machine", eff["leaves_the_machine"]))
    if any(item.startswith("host ") for item in eff["leaves_the_machine"]):
        lines.append("    check names the host, not whether a call there reads or sends")
    lines.append(row("spends", eff["spends"]))
    if eff["unpriced_models"]:
        lines.append(row("unpriced, never free", eff["unpriced_models"]))
    pinned = eff.get("called_on_mock")
    lines.append(row("called even on mock", pinned if pinned is not None else ["this binary did not say"]))
    if pinned:
        lines.append("    a model a task pins is called for real, and billed, under --model mock/echo:")
        lines.append("    read this job's plan with --dry-run, never rehearse it on the mock model")
    lines.append(row("runs programs", eff["runs_programs"]))
    lines.append("Depth     (from nika inspect)")
    lines.append(
        f"  tasks {dep['tasks']} · builtins {len(dep['builtins'])} · when: {len(dep['when'])}"
        f" · failure routes {len(dep['failure_routes'])} · joins {len(dep['joins'])}"
        f" · fan-outs {len(dep['fan_outs'])} · gates {len(dep['gates'])}"
    )
    lines.append(row("builtins", dep["builtins"], "none"))
    lines.append(row("state between runs", dep["state_paths"], "no path is both read and written"))
    lines.append(row("gates", dep["gates"], "none: a run never waits for a person"))
    lines.append("Cost      (per run, as nika check prints it)")
    lines.append(f"  {card['cost']['printed'] or 'check printed no COST line'}")
    if card["cost"]["unbounded"]:
        lines.append(row("no static ceiling", card["cost"]["unbounded"]))
    reasons = card["review"]
    lines.append("Review    " + ("needed: " + ", ".join(reasons) if reasons else "optional: small and local"))
    return "\n".join(lines)


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 1:
        print(__doc__.strip())
        return 3
    path = args[0]
    if not os.path.isfile(path):
        print(f"No card: {path} is not a file")
        return 3
    nika = nika_bin(os.path.dirname(os.path.abspath(path)) or ".")
    checked = call([nika, "check", path, "--json", "--native-strict"])
    report = as_json(checked, "nika check")
    graph = as_json(call([nika, "inspect", path, "--format", "json"]), "nika inspect")
    text = call([nika, "check", path, "--native-strict", "--color", "never"]).stdout
    card = {
        "file": path,
        "workflow": graph.get("workflow") or "?",
        "verdict": verdict(report),
        "effects": effects(report),
        "depth": depth(graph, report),
        "cost": cost(report, text),
    }
    card["effects"]["called_on_mock"] = called_on_mock(
        call([nika, "check", path, "--json", "--native-strict", "--model", "mock/echo"])
    )
    card["review"] = review(card)
    added = None
    replaced = None
    if "--plan" in argv:
        replaced = added_since_plan(path, card["effects"])
        if replaced is not None:
            card["plan_replaced_added"] = replaced
        try:
            with open(plan_path(path), "w", encoding="utf-8") as handle:
                json.dump(card["effects"], handle)
        except OSError as err:
            print(f"The plan could not be remembered ({err}); --since-plan will have nothing to compare.")
    elif "--since-plan" in argv:
        added = added_since_plan(path, card["effects"])
        card["added_since_plan"] = added
    print(json.dumps(card, indent=2) if "--json" in argv else render(card))
    if "--since-plan" in argv and "--json" not in argv:
        if added is None:
            print("Since the plan   no plan was remembered for this file (run with --plan at the plan gate)")
        elif added:
            print("Since the plan   ADDED, not in the card the person approved:")
            print("\n".join(f"  {item}" for item in added))
        else:
            print("Since the plan   no effect was added")
    if replaced is not None and "--json" not in argv:
        if replaced:
            print("Plan             REPLACED the plan remembered for this file. Not in the earlier one, so the person approves them again:")
            print("\n".join(f"  {item}" for item in replaced))
        else:
            print("Plan             replaced the plan remembered for this file; no effect was added")
    if not card["verdict"]["clean"]:
        return 2
    return 4 if added else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
