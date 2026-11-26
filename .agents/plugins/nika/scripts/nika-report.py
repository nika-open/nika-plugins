#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""nika-report — one run, told on one page.

Builds a self-contained HTML page and a Markdown twin from a run's trace:
what ran, what was decided at a gate and by whom, what was written, what
failed or was recovered, what it cost. Every line is read off
`nika trace outputs --json` and the trace's own events; nothing is
estimated, and what the trace does not hold is said to be missing.

The text a run recorded (a gate's question, an error message, a workflow
name) is data: it is escaped on the page, never interpreted, and every
string read from a trace goes through one filter (one printable line,
bounded) before it is printed anywhere, the summary line included. The
page loads nothing from the network. Nothing is published.

The two files are written under the project's `out/` and nowhere else:
`--out` may name a folder inside it, and a folder whose real path leaves
`out/` is refused. Whatever already sits at a target (an older report, a
link) is removed and the file is created anew, so a link is never
followed.

Usage:
  nika-report.py [trace.ndjson] [--out out/<dir>]   (no trace: the newest run)

Exit code: 0 the two files are written · 3 no report (no trace store, no
such trace, nothing readable in it, an output folder outside `out/`) · 127
no nika binary.
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

import datetime
import html
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
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=60)
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


def as_dict(value):
    return value if isinstance(value, dict) else {}


def fields_of(event):
    """The event's fields by key; None for a line that is JSON but not an event."""
    if not isinstance(event, dict):
        return None
    rows = event.get("fields")
    if not isinstance(rows, list):
        return {}
    return {f.get("key"): f.get("value") for f in rows if isinstance(f, dict) and isinstance(f.get("key"), str)}


def events(path):
    rows = []
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                fields = fields_of(event)
                if fields is not None:
                    rows.append((event.get("kind"), fields, event))
    except OSError:
        pass
    return rows


def build(trace, settled, rows):
    start, done, detail, gates, written, skipped = {}, {}, {}, [], [], {}
    started_ns = None
    for kind, fields, event in rows:
        task = fields.get("task") if isinstance(fields.get("task"), str) else None
        if kind == "workflow_started":
            start, started_ns = fields, event.get("timestamp")
        elif kind in ("workflow_completed", "workflow_failed", "workflow_paused"):
            done = fields
        elif task is None:
            continue
        elif kind in ("task_completed", "task_failed"):
            detail[task] = fields
            if str(fields.get("note") or "").endswith("nika:write") and kind == "task_completed":
                try:
                    written.append(str(json.loads(fields.get("output") or '""')))
                except (ValueError, TypeError):
                    pass
        elif kind == "task_skipped":
            skipped[task] = fields.get("note") or ""
        elif kind == "approval_decided":
            gates.append({k: fields.get(k) for k in ("task", "question", "answer", "source", "decision")})
    try:
        budget = json.loads(start.get("budget") or "{}").get("max_cost_usd")
    except (ValueError, TypeError, AttributeError):
        budget = None
    tasks = []
    listed = settled.get("tasks") if isinstance(settled.get("tasks"), list) else []
    for row in [r for r in listed if isinstance(r, dict)] or [{"id": t, "status": "?"} for t in detail]:
        extra = detail.get(row.get("id")) if isinstance(row.get("id"), str) else None
        extra = extra or {}
        tasks.append({
            "id": row.get("id"),
            "verb": row.get("verb") or extra.get("note") or "",
            "status": row.get("status") or "?",
            "code": row.get("error_code") or row.get("recovered_from") or "",
            "message": row.get("error_message") or "",
            "ms": extra.get("duration_ms") or "",
            "model": extra.get("model") or "",
            "tokens_in": extra.get("tokens_in") or "",
            "tokens_out": extra.get("tokens_out") or "",
            "usd": number(extra.get("cost_usd")),
        })
    settlement = as_dict(settled.get("settlement"))
    when = ""
    if isinstance(started_ns, (int, float)) and started_ns > 0:
        try:
            when = datetime.datetime.fromtimestamp(started_ns / 1e9, datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
        except (OverflowError, OSError, ValueError):
            when = ""
    return {
        "trace": trace,
        "workflow": start.get("workflow") or done.get("workflow") or "unknown",
        "state": settled.get("state") or done.get("status") or "unknown",
        "when": when,
        "engine": start.get("engine_version") or "",
        "elapsed_ms": settlement.get("elapsed_ms") or done.get("elapsed_ms") or "",
        "counts": as_dict(settlement.get("tasks")),
        "spend": as_dict(settlement.get("spend")),
        "metered_usd": sum(t["usd"] for t in tasks),
        "ceiling_usd": budget,
        "tasks": tasks,
        "gates": gates,
        "written": written,
        "skipped": skipped,
        "mock": any(str(t["model"]).startswith("mock/") for t in tasks),
        "paused_at": done.get("task") if settled.get("state") == "paused" else None,
    }


def facts(report):
    """The summary rows, shared by both renderings."""
    counts, spend = report["counts"], report["spend"]
    rows = [
        ("Workflow", report["workflow"]),
        ("Result", str(report["state"]) + (f" at `{report['paused_at']}`: waiting for an answer" if report["paused_at"] else "")),
        ("Started", report["when"] or "not recorded"),
        ("Took", f"{report['elapsed_ms']} ms" if report["elapsed_ms"] != "" else "not recorded"),
        ("Tasks", ", ".join(f"{v} {k}" for k, v in counts.items() if v and k != "total") or "not recorded"),
        ("Metered spend", f"${report['metered_usd']:.4f}" + (f" of a ${number(report['ceiling_usd']):.2f} ceiling" if number(report["ceiling_usd"]) else " (no ceiling on this run)")),
        ("Calls", f"{spend.get('priced_calls', '?')} priced, {spend.get('unpriced_calls', '?')} unpriced ({spend.get('qualifier', 'not recorded')})"),
        ("Engine", report["engine"] or "not recorded"),
        ("Trace", report["trace"]),
    ]
    notes = []
    if report["mock"]:
        notes.append("This was a rehearsal: a mock model echoed the prompts. Tools, writes and fetches were real.")
    if spend.get("unpriced_calls"):
        notes.append("An unpriced call is not a free call: a local or seat model is billed elsewhere, or in energy.")
    notes.append("Metered spend counts what the engine priced on output. Input billing by a provider is not in the trace.")
    notes.append("A settled run says every task ended. It does not say a model's answer was right, or what a remote server did with a call.")
    return rows, notes


def cell(value, limit=300):
    """Text read from a trace, as data: one printable line, no table or code mark, bounded."""
    flat = " ".join(str(value).replace("|", "\\|").replace("`", "'").split())
    flat = "".join(ch for ch in flat if ch.isprintable())
    return flat if len(flat) <= limit else flat[:limit] + "…"


def css(value):
    """A status as a class name: letters only, or nothing."""
    return re.sub(r"[^a-z_-]", "", str(value).lower())[:24]


def markdown(report):
    rows, notes = facts(report)
    out = [f"# Run report · {cell(report['workflow'])}", ""]
    out += [f"- **{k}**: {cell(v)}" for k, v in rows]
    if report["gates"]:
        out += ["", "## Decisions at a gate", ""]
        out += [f"- `{cell(g['task'])}`: asked « {cell(g['question'])} », answered `{cell(g['answer'])}` ({cell(g['source'])})" for g in report["gates"]]
    if report["written"]:
        out += ["", "## Written", ""] + [f"- `{cell(p)}`" for p in report["written"]]
    bad = [t for t in report["tasks"] if t["status"] in ("failed", "recovered")]
    if bad:
        out += ["", "## Failed or recovered", ""]
        out += [f"- `{cell(t['id'])}` {cell(t['status'], 24)}: {cell(t['code'])} {cell(t['message'])}".rstrip() for t in bad]
    if report["skipped"]:
        out += ["", "## Branches not taken", ""]
        out += [f"- `{cell(k)}` was skipped" + (f" ({cell(v)})" if v else "") for k, v in report["skipped"].items()]
    out += ["", "## Tasks", "", "| Task | What | Status | ms | Model | Tokens in/out | USD |", "|---|---|---|---|---|---|---|"]
    for t in report["tasks"]:
        tokens = f"{t['tokens_in']}/{t['tokens_out']}" if t["tokens_in"] or t["tokens_out"] else ""
        usd = f"{t['usd']:.4f}" if t["usd"] else ""
        out.append(f"| {cell(t['id'])} | {cell(t['verb'])} | {cell(t['status'], 24)} | {cell(t['ms'], 24)} | {cell(t['model'])} | {cell(tokens, 48)} | {usd} |")
    out += ["", "## Read this with", ""] + [f"- {n}" for n in notes]
    return "\n".join(out) + "\n"


STYLE = """:root{--bg:#fbfaf7;--fg:#1c1b19;--muted:#6b675f;--line:#dedad2;--ok:#1f7a4d;--bad:#b3261e;--warn:#9a6700}
@media (prefers-color-scheme:dark){:root{--bg:#141412;--fg:#ecebe6;--muted:#a09c93;--line:#34322d;--ok:#57c08a;--bad:#f2857c;--warn:#e0b050}}
body{background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif;margin:0;padding:24px 16px}
main{max-width:920px;margin:0 auto}h1{font-size:22px;margin:0 0 4px}h2{font-size:16px;margin:28px 0 8px}
dl{display:grid;grid-template-columns:max-content 1fr;gap:4px 16px;margin:12px 0}dt{color:var(--muted)}dd{margin:0;overflow-wrap:anywhere}
.wrap{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:14px}th,td{text-align:left;padding:6px 10px;border-bottom:1px solid var(--line);vertical-align:top}
th{color:var(--muted);font-weight:500}code{font:13px ui-monospace,monospace}
.succeeded,.ok{color:var(--ok)}.failed{color:var(--bad)}.recovered,.paused,.skipped,.cancelled{color:var(--warn)}li{margin:4px 0}.note{color:var(--muted)}"""


def page(report):
    esc = html.escape
    rows, notes = facts(report)
    out = ["<!doctype html>", '<html lang="en"><head><meta charset="utf-8">',
           '<meta name="viewport" content="width=device-width,initial-scale=1">',
           f"<title>Run report · {esc(str(report['workflow']))}</title><style>{STYLE}</style></head><body><main>",
           f"<h1>Run report · {esc(str(report['workflow']))}</h1>",
           f'<p class="{css(report["state"])}">{esc(cell(report["state"]))}</p><dl>']
    out += [f"<dt>{esc(k)}</dt><dd>{esc(str(v).replace('`', ''))}</dd>" for k, v in rows]
    out.append("</dl>")
    if report["gates"]:
        out.append("<h2>Decisions at a gate</h2><ul>")
        out += [f"<li><code>{esc(str(g['task']))}</code>: asked « {esc(str(g['question']))} », answered <code>{esc(str(g['answer']))}</code> ({esc(str(g['source']))})</li>" for g in report["gates"]]
        out.append("</ul>")
    if report["written"]:
        out.append("<h2>Written</h2><ul>" + "".join(f"<li><code>{esc(p)}</code></li>" for p in report["written"]) + "</ul>")
    bad = [t for t in report["tasks"] if t["status"] in ("failed", "recovered")]
    if bad:
        out.append("<h2>Failed or recovered</h2><ul>")
        out += [f'<li><code>{esc(str(t["id"]))}</code> <span class="{css(t["status"])}">{esc(str(t["status"]))}</span>: {esc(str(t["code"]))} {esc(str(t["message"]))}</li>' for t in bad]
        out.append("</ul>")
    if report["skipped"]:
        out.append("<h2>Branches not taken</h2><ul>")
        out += [f"<li><code>{esc(str(k))}</code> was skipped" + (f" ({esc(str(v))})" if v else "") + "</li>" for k, v in report["skipped"].items()]
        out.append("</ul>")
    out.append('<h2>Tasks</h2><div class="wrap"><table><tr><th>Task</th><th>What</th><th>Status</th><th>ms</th><th>Model</th><th>Tokens in/out</th><th>USD</th></tr>')
    for t in report["tasks"]:
        tokens = f"{t['tokens_in']}/{t['tokens_out']}" if t["tokens_in"] or t["tokens_out"] else ""
        usd = f"{t['usd']:.4f}" if t["usd"] else ""
        out.append(f'<tr><td><code>{esc(str(t["id"]))}</code></td><td>{esc(str(t["verb"]))}</td><td class="{css(t["status"])}">{esc(str(t["status"]))}</td><td>{esc(str(t["ms"]))}</td><td>{esc(str(t["model"]))}</td><td>{esc(tokens)}</td><td>{usd}</td></tr>')
    out.append("</table></div><h2>Read this with</h2><ul>" + "".join(f'<li class="note">{esc(n)}</li>' for n in notes) + "</ul></main></body></html>")
    return "\n".join(out) + "\n"


def out_folder(out_dir):
    """The real folder to write in, or None when it leaves the project's `out/`."""
    base = os.path.join(os.path.realpath(os.getcwd()), "out")
    real = os.path.realpath(out_dir)
    try:
        inside = os.path.commonpath([base, real]) == base
    except ValueError:
        inside = False
    return real if inside else None


def write_new(path, text):
    """Write one report file as a new file: whatever sat at the path is removed, not followed."""
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    with os.fdopen(os.open(path, flags, 0o644), "w", encoding="utf-8") as handle:
        handle.write(text)


def main(argv):
    out_dir, args, skip = "out", [], False
    for i, arg in enumerate(argv):
        if skip:
            skip = False
        elif arg == "--out" and i + 1 < len(argv):
            out_dir, skip = argv[i + 1], True
        elif not arg.startswith("--"):
            args.append(arg)
    folder = out_folder(out_dir)
    if folder is None:
        print(f"No report: {out_dir} leads outside this project's out/ folder. The report is written under out/ only (name a folder inside it with --out out/<name>).")
        return 3
    try:
        nika = nika_bin(os.getcwd())
    except FileNotFoundError:
        print("nika is not installed: curl -LsSf https://nika.sh/install.sh | sh")
        return 127
    trace = args[0] if args else None
    if trace is None:
        listed = ask([nika, "trace", "ls", "--json"]).get("traces")
        listed = [t for t in listed if isinstance(t, dict)] if isinstance(listed, list) else []
        newest = [t for t in listed if t.get("newest")] or listed[:1]
        if not newest:
            print("No report: no run has been recorded in this folder yet (.nika/traces is empty or absent).")
            return 3
        trace = newest[0].get("path")
    if not isinstance(trace, str) or not os.path.isfile(trace):
        print(f"No report: {cell(trace, 200)} is not a trace file.")
        return 3
    rows = events(trace)
    if not rows:
        print(f"No report: nothing readable in {cell(trace, 200)}.")
        return 3
    report = build(trace, ask([nika, "trace", "outputs", trace, "--json"]), rows)
    stem = re.sub(r"[^A-Za-z0-9_.-]", "_", os.path.splitext(os.path.basename(trace))[0])[:120] or "run"
    targets = [(os.path.join(folder, f"nika-report-{stem}.html"), page(report)),
               (os.path.join(folder, f"nika-report-{stem}.md"), markdown(report))]
    try:
        os.makedirs(folder, exist_ok=True)
        if os.path.realpath(folder) != folder:
            raise OSError("the folder became a link while it was made")
        for path, text in targets:
            write_new(path, text)
    except OSError as err:
        print(f"No report: could not write under {out_dir} ({err}).")
        return 3
    # The name and the state come from the trace: filtered like every cell.
    print(f"{cell(report['workflow'], 80)} · {cell(report['state'], 40)} · {len(report['tasks'])} tasks · metered ${report['metered_usd']:.4f}")
    for path, _ in targets:
        print(f"wrote {os.path.relpath(path)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
