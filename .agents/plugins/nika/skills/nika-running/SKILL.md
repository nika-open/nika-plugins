---
name: nika-running
description: "Run, approve, resume and schedule Nika workflows for someone who should not have to read engine output. Use when the user wants a task done again or on a schedule ('every Monday', 'for each file', 'do the same as last time', a batch of items), asks what a workflow will do or cost, wants to run one, or when a run is waiting for an answer. The word Nika does not need to appear."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-facts.sh *), Bash(${CLAUDE_PLUGIN_ROOT}/bin/nika-kit *), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-intent.py *), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-verdict.py *), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-pick-model.sh *), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-pending.py *)
---

# Running Nika for a person, not for a terminal

The engine is exact and wordy. The person wants three things: to know
what will happen, to say yes once, and to get the result. Everything
here serves that.

## What this machine has, right now

In the plugin, the line below runs when this skill loads and prints the
binary in use, the model names it knows and how many runs wait for an answer. If
nothing follows it (the host does not run it, or a policy disabled it), ask
the binary yourself: `nika --version`, `nika catalog`, `nika trace ls`.

!`"${CLAUDE_PLUGIN_ROOT}/scripts/nika-facts.sh" || true`

## Where the helpers are

The four helper scripts named below ship with this plugin, in its own
`scripts/` folder. They are not in the project and not next to this file.
Run each by the full path written here, as its own command (no `cd`, no
`&&`), so the path is the first word.

The same holds for every `nika` command: one command per call, with
nothing chained to it (no `&&`, no `|`, no `; echo`). A chained line is
judged as a whole and can be refused. A pipe also hides the exit code,
and exit 4 is how you learn that a run is waiting for an answer.

## What needs the person, and what never does

Their yes is needed to start a run with its ceiling (once per run), to answer
a gate, to raise a ceiling or move to a paid model, to run or resume again a
run that stopped, and to switch a schedule on. Checking, saying the verdict, reading a trace, listing the runs that wait
and showing a plan with `nika run <file> --dry-run` never wait for them.

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
   includes a spending cap, said as a number and passed as
   `--max-cost-usd <n>`. The cap set for this plugin is
   « ${user_config.max_cost_usd} »: use it when that reads as a number. When
   it reads as a placeholder, this host did not fill it in: never pass it,
   and take a number at or above the cost line of the verdict. The user can
   always name another one.
3. **You choose the model.**
   `"${CLAUDE_PLUGIN_ROOT}/scripts/nika-pick-model.sh"` prints the flags
   that work on this machine. If nothing is ready, offer the two or three
   ways out as a short choice, plus a rehearsal on `mock/echo`. A person
   must never meet a provider error on their first run.
4. **Questions are asked here.** When a run pauses (exit 4), read the
   question from the paused frame, show it with the real destination and
   cost, and wait for the person's own answer. Resume at once, with the
   same flags as the first run (its `--model` or `--access` route among
   them: a resume that drops it is refused, exit 3) and the same `--var`
   values: an answer is accepted for 15 minutes after the pause. You never answer a gate yourself, never pass `--answer` on your
   own initiative, and permission to run is not an answer.
   The gate rule is stated once, in the `nika-authoring` skill's
   `references/job-anatomy.md` under « Approve once, then let it run ». A
   scheduled workflow that keeps a gate pauses at every fire on 0.125.0
   (exit 4); say so, and offer to design the gate out where the risk
   allows.
5. **Two files, not thirty.** A new project is a workflow and `nika.yaml`.
   Run the full `nika init` only when asked, and say how many files it
   adds.
6. **One sentence, then the offer of detail.** Result first. A failure is
   one sentence and one fix. Hints that repeat become one line ("same
   remark on 3 steps"). The detail is always one question away.

## A run that takes a while

Start a long run in the background when the host's shell tool can do that
and tell you when it ends. Say the ceiling, say you will come back when the
run ends or asks something, and carry on with what the person asked next.
When it ends, the exit code comes first: 0 it settled, 4 it waits for an
answer, 2 or 3 it was refused before anything ran, 1 or 130 it stopped.
Where the host cannot run in the background, run it in the foreground:
nothing else changes.

## A run that was refused, a run that stopped

Exit 2 or 3 is a refusal before anything ran: no step ran, nothing was
paid, and the run left no trace. Do not read a trace for it: with no trace
named, `nika trace outputs` reads the latest one in the project, which is
an older run. Exit 2 is the file (the findings `nika check` prints, or a
cost floor above the ceiling), exit 3 the environment (most often no model
route, `NIKA-1800`). Fix that and run from the start.

Exit 1 or 130 is a run that stopped. Read it before any second run. It
already had effects (files written, calls paid, maybe something sent) and a
run from the start repeats them. `nika trace outputs <trace> --json` names
the task that stopped and its code; `nika explain <code>` teaches the fix.
After the repair, check the file. Running again is the person's yes; with
it, prefer `nika run <file> <same flags and vars> --resume <trace>`, which
skips what settled, and read its first line: a trace that « carries no
resume keys » runs everything again. This is the last step of every run
that stopped, whether or not the host reminded you of it.

## Runs that wait

A run can be waiting without anyone knowing: a scheduled run parked at
night, a run left before a meeting, a background run that paused while you
were elsewhere. A waiting run is state on disk, not something to remember:
`nika trace ls` lists it in any session, on any host. When you start work in
a Nika project, after any scheduled run, and when a long conversation was
summarized, list them again: run
`"${CLAUDE_PLUGIN_ROOT}/scripts/nika-pending.py"`, or read
`nika trace ls --json` and the paused frame of each paused trace. If
something waits, say it first: which workflow, the question, how long ago.
`/nika:pending` handles the answer.

## An approval the person gives every time

After they answered the same gate of the same workflow more than once, look
whether this binary can remember an approval:
`"${CLAUDE_PLUGIN_ROOT}/bin/nika-kit" --has consent`, or simply whether
`nika consent --help` answers. When it does, say so once, in one line, and
show them the command its help prints: they run the grant, you never do, and
you never create one on their behalf. When it does not, say nothing about it
and keep asking at each gate.

## What the plugin already does for you

- **Diagnostics arrive on their own.** The plugin starts `nika lsp`: after
  each edit of a `.nika` file the findings are already in your context, in
  a few milliseconds. Fix them before you say anything about the file.
- **A waiting run is announced.** At session start, and while this skill is
  in use, a run that pauses for an answer shows up as a short notice. Before
  a long conversation is summarized, the runs that wait and the workflows
  changed in the session are written into the summary.
- **A run is followed without watching it.** While this skill is in use, one
  line arrives when a task fails, is recovered or pauses, and when metered
  spend passes half and nine tenths of the ceiling. A task that succeeds
  prints nothing.
- **A run that stopped comes back with a reminder** to read its trace before
  a second run.

- **A repeatable request is flagged once, already read.** When a prompt
  sounds like a schedule, a batch or "do it again", you get one hint per
  session. When the engine can read the sentence, the hint already holds
  its reading (pieces, schedule, questions). Offer once; if the user says
  no, drop it.

These exist in interactive Claude Code sessions. Everything above holds
without them: they repeat a rule, they do not replace it.

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
