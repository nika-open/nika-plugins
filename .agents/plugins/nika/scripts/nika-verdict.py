#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""nika-verdict — the audit in plain words.

`nika check --json` is the source of truth; this script only re-tells it
in sentences a person can approve in ten seconds: what the file reads,
where it sends, what it can cost, whether it asks first, and whether it
is ready. No engine code, no second opinion: every line is read off the
payload, and an unknown shape is reported as unknown, never guessed.

Usage:
  nika-verdict.py <file.nika> [--model <provider/model>] [--json]

Exit code: the one `nika check` returned (0 ready · 2 findings · other =
the check itself could not run; 124 = it did not answer within 60 s).

NIKA_KIT_TIMEOUT_SECONDS replaces the 60 s given to the binary (tests).
"""
import json
import os
import subprocess
import sys

KNOWN_KINDS = {
    "trifecta": (
        "It reads private files, takes in outside content and can send data "
        "out, with no question asked first. Add an approval step before the reads."
    ),
}


def nika_bin(location):
    """The binary the kit resolved (bin/nika-kit), else NIKA_BIN, else PATH."""
    kit = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bin", "nika-kit")
    if os.access(kit, os.X_OK):
        try:
            out = subprocess.run([kit, "--path", location], capture_output=True, text=True, check=False, timeout=15)
            if out.returncode == 0 and out.stdout.strip():
                return out.stdout.strip()
        except (OSError, subprocess.SubprocessError):
            pass
    return os.environ.get("NIKA_BIN") or "nika"


def seconds():
    try:
        return float(os.environ.get("NIKA_KIT_TIMEOUT_SECONDS") or 60)
    except ValueError:
        return 60.0


def run_check(path, model):
    cmd = [nika_bin(os.path.dirname(os.path.abspath(path))), "check", path, "--json"]
    if model:
        cmd += ["--model", model]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=seconds())
    except FileNotFoundError:
        print("nika is not installed: curl -LsSf https://nika.sh/install.sh | sh")
        sys.exit(127)
    except subprocess.TimeoutExpired:
        print(f"The check did not answer within {seconds():g} s, so there is no verdict on this file.")
        sys.exit(124)
    try:
        return proc.returncode, json.loads(proc.stdout)
    except json.JSONDecodeError:
        tail = (proc.stderr or proc.stdout).strip().splitlines()[-1:] or ["no output"]
        print(f"The check could not read this file: {tail[0][:200]}")
        sys.exit(proc.returncode or 1)


def listing(items, empty):
    items = [str(i) for i in items if i]
    if not items:
        return empty
    if len(items) > 4:
        return ", ".join(items[:4]) + f" and {len(items) - 4} more"
    return ", ".join(items)


def money(value):
    if value >= 1:
        return f"${value:.2f}"
    return f"${value:.4f}".rstrip("0").rstrip(".") if value else "$0"


def verdict(report):
    needed = (report.get("permits") or {}).get("needed") or {}
    fs = needed.get("fs") or {}
    net = needed.get("net") or {}
    tools = needed.get("tools") or []
    journey = report.get("data_journey") or {}

    mcp_tools = [t for t in tools if t.startswith("mcp:")]
    lines = []
    lines.append("Reads: " + listing(fs.get("read", []), "no file on your disk"))
    writes = listing(fs.get("write", []), "")
    if writes:
        lines.append("Writes: " + writes)
    reach = list(net.get("http", []))
    lines.append("Can reach: " + listing(reach, "nothing outside this machine"))
    if mcp_tools:
        lines.append(
            "Uses connected tools: "
            + listing(mcp_tools, "")
            + " (the check does not know what these tools read or send)"
        )
    if needed.get("exec"):
        lines.append("Runs programs on this machine: yes")

    seen = []
    for endpoint in journey.get("model_endpoints", []):
        if endpoint.get("provider") == "mock":
            where = "a stand-in that repeats the prompt, for rehearsals"
        elif endpoint.get("locus") == "local":
            where = "on this machine"
        else:
            where = "in the cloud"
        text = f"{endpoint.get('model', 'unknown model')} ({where}"
        if endpoint.get("locus") != "local":
            keep = endpoint.get("retention")
            trains = endpoint.get("trains")
            if keep not in (None, "", "unknown"):
                text += f", keeps data {keep} days"
            if trains == "no":
                text += ", does not train on it"
            elif trains == "yes":
                text += ", may train on it"
        text += ")"
        if text not in seen:
            seen.append(text)
    if seen:
        lines.append("Model: " + listing(seen, ""))

    cost = report.get("cost") or {}
    tasks = cost.get("tasks") or []
    if not tasks:
        lines.append("Cost: no model call")
    elif cost.get("has_unbounded"):
        lines.append("Cost: no upper limit, because a step has no token cap")
    else:
        top = cost.get("bounded_total_usd") or 0.0
        if top == 0:
            lines.append("Cost: not priced (a local or stand-in model)")
        else:
            lines.append(f"Cost: at most {money(top)} of model output per run (prompts not counted)")

    if "nika:prompt" in tools:
        gates = [m.get("gate") for m in report.get("trifecta_mitigations", []) if m.get("gate")]
        which = f" (step `{gates[0]}`)" if gates else ""
        lines.append(f"Asks you first: yes{which}; with nobody there, the run waits")
    else:
        lines.append("Asks you first: no")

    findings = report.get("findings") or []
    if report.get("clean") and not findings:
        lines.append("Verdict: ready to run")
    else:
        lines.append(f"Verdict: not ready, {len(findings)} thing(s) to fix")
        for item in findings[:3]:
            plain = KNOWN_KINDS.get(item.get("kind"))
            if not plain:
                plain = (item.get("message") or "").split(" — ")[0].split(" -- ")[0][:160]
            ref = item.get("code") or "no code"
            lines.append(f"  - {plain} (ref {ref})")
        if len(findings) > 3:
            lines.append(f"  - and {len(findings) - 3} more")
    return lines


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    if not args:
        print(__doc__.strip().splitlines()[0])
        print("usage: nika-verdict.py <file.nika> [--model <provider/model>] [--json]")
        return 2
    model = None
    if "--model" in argv:
        index = argv.index("--model")
        if index + 1 < len(argv):
            model = argv[index + 1]
            args = [a for a in args if a != model]
    code, report = run_check(args[0], model)
    lines = verdict(report)
    if "--json" in argv:
        print(json.dumps({"exit": code, "ready": bool(report.get("clean")), "lines": lines}))
    else:
        print("\n".join(lines))
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
