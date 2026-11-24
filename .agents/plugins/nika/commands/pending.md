---
description: Show the Nika runs that are waiting for an answer, with their question, and resume the one the user answers
argument-hint: "[project-dir]"
allowed-tools: Bash(nika trace:*), Bash(nika run:*), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-pending.py *), Read, Glob
---

A paused run waits silently: a scheduled run set aside at night, a run
left during lunch. Find them and let the user answer in one step.

1. Run `"${CLAUDE_PLUGIN_ROOT}/scripts/nika-pending.py" $ARGUMENTS`
   (add `--json` to read it as data). Exit 0 means nothing waits: say so
   in one line and stop. If the script is unavailable, use
   `nika trace ls --json` and read the `workflow_paused` frame of each
   paused trace; a paused trace whose run id appears as another trace's
   `resumed_from` was already answered.
2. For each waiting run, show three things only: which workflow, the
   question as it was asked, and how long ago. Several runs asking the
   same question? Show them together and ask once.
3. Wait for the user's own answer. **Never answer for them.**
4. Resume with the line the script printed. It needs the same `--var`
   values as the original run: the trace keeps where each input came
   from, not its value. If you do not have them, ask.
5. If the answer window has closed (15 minutes after the pause), say it
   plainly: resuming will ask again, and the user answers right away.
6. Report the result of the resumed run, then one line on cost and where
   the record is.
