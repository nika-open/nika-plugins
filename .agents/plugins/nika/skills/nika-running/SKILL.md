---
name: nika-running
description: "Run, approve, resume and schedule Nika workflows for someone who should not have to read engine output. Use when the user wants a task done again or on a schedule ('every Monday', 'for each file', 'do the same as last time', a batch of items), asks what a workflow will do or cost, wants to run one, or when a run is waiting for an answer. The word Nika does not need to appear."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-intent.py *), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-verdict.py *), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-pick-model.sh *), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-pending.py *)
---

# Running Nika for a person, not for a terminal

The engine is exact and wordy. The person wants three things: to know
what will happen, to say yes once, and to get the result. Everything
here serves that.

## Where the helpers are

The four helper scripts named below ship with this plugin, in its own
`scripts/` folder. They are not in the project and not next to this file.
Run each by the full path written here, as its own command (no `cd`, no
`&&`), so the path is the first word.

The same holds for every `nika` command: one command per call, with
nothing chained to it (no `&&`, no `|`, no `; echo`). A chained line is
judged as a whole and can be refused. A pipe also hides the exit code,
and exit 4 is how you learn that a run is waiting for an answer.

## The seven rules

0. **Their sentence first.** When a workflow has to be created, hand the
   user's own sentence, unchanged, to
   `"${CLAUDE_PLUGIN_ROOT}/scripts/nika-intent.py" "<sentence>"` before
   you write a line. The engine reads English and French with no
   model call: it prints the pieces of the sentence, the step each piece
   became, a schedule down to its cron line, and the questions only the
   user can answer. Show that reading, ask only those questions, and keep
   the file with `--write`. Write by hand only when the engine cannot read
   the sentence (exit 3), and then say that the mapping from words to
   steps is yours, not the engine's. If an instruction lost a verb of the
   request, the helper names it: put it back.
1. **Plain verdict, three to six lines.** Before any run, say what the
   file reads, what it can reach, which model sees the data, what it can
   cost, whether it asks first, and whether it is ready. Use
   `"${CLAUDE_PLUGIN_ROOT}/scripts/nika-verdict.py" <file>`; it reads
   `nika check --json` and invents nothing. No raw check output, no `NIKA-…` code unless asked.
2. **One yes.** Ask once, with the verdict above the question. The yes
   includes a spending cap: `--max-cost-usd ${user_config.max_cost_usd}`
   unless the user names another one, and you say the number.
3. **You choose the model.**
   `"${CLAUDE_PLUGIN_ROOT}/scripts/nika-pick-model.sh"` prints the flags
   that work on this machine. If nothing is ready, offer the two or three
   ways out as a short choice, plus a rehearsal on `mock/echo`. A person
   must never meet a provider error on their first run.
4. **Questions are asked here.** When a run pauses (exit 4), read the
   question from the paused frame, show it with the real destination and
   cost, and wait for the person's own answer. Resume at once, with the
   same `--var` values: an answer is accepted for 15 minutes after the
   pause. You never answer a gate yourself, and permission to run is not
   an answer.
5. **Two files, not thirty.** A new project is a workflow and `nika.yaml`.
   Run the full `nika init` only when asked, and say how many files it
   adds.
6. **One sentence, then the offer of detail.** Result first. A failure is
   one sentence and one fix. Hints that repeat become one line ("same
   remark on 3 steps"). The detail is always one question away.

## Runs that wait

A run can be waiting without anyone knowing: a scheduled run parked at
night, a run left before a meeting. When you start work in a Nika
project, and after any scheduled run, run
`"${CLAUDE_PLUGIN_ROOT}/scripts/nika-pending.py"`. If something waits,
say it first: which workflow, the question, how long ago. `/nika:pending` handles the answer.

## What the plugin already does for you

- **Diagnostics arrive on their own.** The plugin starts `nika lsp`: after
  each edit of a `.nika` file the findings are already in your context, in
  a few milliseconds. Fix them before you say anything about the file.
- **A waiting run is announced.** At session start, and while this skill is
  in use, a run that pauses for an answer shows up as a short notice.
- **A repeatable request is flagged once, already read.** When a prompt
  sounds like a schedule, a batch or "do it again", you get one hint per
  session. When the engine can read the sentence, the hint already holds
  its reading (pieces, schedule, questions). Offer once; if the user says
  no, drop it.

## Words

Say what the person would say. The engine's words stay in the file and
in the reference.

| Engine word | Say |
|---|---|
| permits | what the file is allowed to touch |
| lethal trifecta, Rule of Two | private data, outside content and a way out, all three together |
| gate, blocking prompt | a question you have to answer |
| seat, harness access | your Claude Code or Codex subscription |
| beat, arm | schedule |
| worst-case output ceiling | the most the model's answers can cost |
| trace | the record of the run |

## What this skill does not do

It does not weaken a check, pre-answer a question, or hide a refusal. If
the check says no, the person hears no, in one sentence, with the fix.
