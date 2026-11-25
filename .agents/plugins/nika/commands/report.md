---
description: Build a page a person can read from a run's record — what ran, what was decided at a gate, what was written, what failed and what it cost
argument-hint: "[trace.ndjson]"
allowed-tools: Bash(nika trace:*), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-report.py *), Read, Glob
---

A run leaves a record that only the engine reads comfortably. Turn it into
one page for the person who asked for the work. Target: `$ARGUMENTS` (no
trace named: the newest run in this folder).

1. From the project folder, run
   `"${CLAUDE_PLUGIN_ROOT}/scripts/nika-report.py" $ARGUMENTS`. It writes two
   files under the project's `out/` and nowhere else (`--out out/<name>`
   picks a folder inside it; a folder that leads outside `out/` is refused):
   `nika-report-<run>.html`, one self-contained page that loads nothing from
   the network, and its Markdown twin. Exit 3 means no report and says why
   (no run recorded, no such trace, a folder outside `out/`); exit 127 means
   no binary.
2. Read the Markdown twin, then tell the person three lines: the result,
   what failed, was recovered or was skipped, and the cost with its unpriced
   part named. Give both paths.
3. Keep to what the record holds. Every line of the page is read off
   `nika trace outputs --json` and the trace's own events; its last section
   says what the record does not judge. Add no estimate of your own, and do
   not call an unpriced call free.
4. Without the kit's scripts, read `nika trace outputs <trace> --json`
   (and `nika trace show <trace>` for the text form), write the same
   sections by hand in Markdown, and say the page is hand-written.

**Publishing is the person's choice.** When the host has a tool that
publishes a page and they may want to share this one, offer it in one line.
Publish only on their yes, and never on your own: a run report can carry
file paths, a gate's question and error text from their data.
