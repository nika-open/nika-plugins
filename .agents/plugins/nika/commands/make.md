---
description: Turn the user's own sentence into a checked workflow — the engine reads the sentence first, the plan is approved once, the file is built phase by phase, reviewed cold and handed over with its verdict
argument-hint: <what the workflow should do, in the user's words>
allowed-tools: Bash(nika check:*), Bash(nika inspect:*), Bash(nika compile:*), Bash(nika catalog:*), Bash(nika list:*), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-intent.py *), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-pick-model.sh *), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-card.py *), Read, Write, Edit, Glob
---

Start from the user's sentence, unchanged: `$ARGUMENTS`. Do not rephrase,
translate or "improve" it before the engine has read it. The engine reads
English and French, and its reading is what the user will check.

**What needs the person, and what never does.** Their yes is needed for
five things: the plan (once), the answer to a gate, an effect their sentence
did not name (a send, a host, a program, an MCP server, a write outside
their folder), a paid model route, and publishing anything. Nothing else
waits for them: checking, drawing the card, repairing a finding, adding
validation, state or a report, writing the workflow and what it produces
under the project's `out/`, a rehearsal on the mock model of a job whose
card shows nothing leaving the machine and no model called even on mock,
and a `--dry-run` of any job (it shows the plan and executes no effect). Do the second list without asking;
never do the first without a yes.

**Without the kit's scripts** (a host that does not resolve
`${CLAUDE_PLUGIN_ROOT}`), every step below still holds with the binary
alone: `nika compile --json -- "<the sentence>"` is the engine's reading,
`nika catalog` lists the model routes, and the card is
`nika check <file> --json --native-strict` read beside
`nika inspect <file> --format json`. Write down what the job reads, writes,
sends, spends and runs from those two, keep that list as the approved plan,
and compare it again before the hand-over.

**1 · Let the engine read it.** Run
`"${CLAUDE_PLUGIN_ROOT}/scripts/nika-intent.py" "<the sentence>"`.
No model is called and no workflow is written. It prints the pieces of the
sentence, the step each piece became, a schedule down to its cron line, the
questions only the user can answer, and a verdict (exit 0 ready · 2 needs
answers · 3 the engine cannot read this sentence on its own).

**2 · Show the reading.** In the user's language, one line per piece:
their words, then what the workflow does with them. Name any piece that
was left out. This is the moment the user sees that nothing was dropped
and no effect was added.

**3 · Ask only what the engine asks (exit 2).** Put the required questions
in ONE message (use the question tool when there is one). For `model`, run
`"${CLAUDE_PLUGIN_ROOT}/scripts/nika-pick-model.sh"` and propose its
answer; the user confirms. Add no question of your own. Leave the optional
schedule questions alone unless the user wants the schedule switched on.
Never answer a question yourself: a missing address or path is asked, not
guessed.

**4 · Get the facts before the design.** When the design depends on
something you have not seen (the shape of a file the job reads, a workflow
that already does half of it, which builtin fits), find out first: hand the
question to the `nika-scout` role where the host has subagents, or make the
same lookups yourself (`nika list`, `nika catalog --tools`, the first lines
of a file). A design built on a guessed shape is repaired three times.

**5 · Write the first version.** Run the helper again with
`--answer KEY=VALUE` for each answer and `--write workflows/<kebab-name>.nika`;
exit 0 writes the file. When the engine could not read the sentence
(exit 3), write a first version by hand with the `nika-authoring` skill:
the pieces the helper listed are your checklist, every piece gets a step,
and `permits:` stays at what the steps really touch. If "The model will be
told" flags a verb of the request that the instruction lost, put it back.
Say plainly which mapping is the engine's and which is yours.

**6 · Plan gate: one yes for the whole job.** Run
`"${CLAUDE_PLUGIN_ROOT}/scripts/nika-card.py" <file> --plan` and show, in
the user's language:

- the phases you will build (gather, normalize, judge, act, report) and
  what each adds to the first version, read from the authoring skill's
  `references/capabilities.md` and `references/job-anatomy.md`;
- the card as the script prints it: what the job reads, writes in the
  project, sends out of the machine, spends and runs, and the cost per run.
  It is read off `nika check` and `nika inspect`; do not replace a line of
  it with your own reading of the file;
- one line per upgrade that would widen the card (a new send, host, paid
  model, seat route, program or MCP server, a write outside their folder):
  offers, each added only on its own yes.

Then three answers: **build**, **revise**, **drop**. Ask nothing the
checker already settled. `--plan` remembers the card the user approved.

**7 · Build by phase.** Add one phase, run `nika check`, repair what it
finds, then add the next: validation of what the job reads, state between
runs and only-new reporting when it repeats, dedupe, a bounded fan-out,
retry and a marked degraded result for a dead source, typed schemas with
`max_tokens`, a `nika:assert` budget, a `nika:chart` when there are numbers,
a run report built as a value with its `nika:inspect` cost. Each stays
inside the hosts, files, folders and models the user approved. If an
addition turns a clean check into `NIKA-SEC-009`, take it back out and
offer it: do not repair it with a gate. On a long job the `nika-author`
role can do this step; give it the approved plan.

**The gate rule** is stated once, in the authoring skill's
`references/job-anatomy.md` under « Approve once, then let it run »: follow
it. In short: at most one gate, where `nika check` requires one, before a
send or before an effect that cannot be undone, and never for cost.

**8 · Done means three things.** The check is clean
(`nika check <file> --json --native-strict`); the job was rehearsed; every
file the rehearsal wrote was opened and parsed. A job whose card shows
nothing leaving the machine and no model called even on mock is rehearsed
with `nika run <file> --model mock/echo --max-cost-usd 0.10`. The mock
replaces the workflow's own model and nothing else: tools, writes and sends
stay real, and a model pinned on a task is still called for real and billed
(`nika check` prints an `envelope-model` hint for each such task). So a job
that sends, reaches a host or pins a model on a task gets
`nika run <file> --dry-run` instead, never a mock run, and the hand-over
says its effects were not exercised. When the person said not to run it, do not rehearse on the mock model
either: read the plan with `nika run <file> --dry-run`, which executes
nothing, and say in the hand-over that the job was not rehearsed. Then run
`"${CLAUDE_PLUGIN_ROOT}/scripts/nika-card.py" <file> --since-plan`: an
effect the approved card did not show (exit 4) comes back out, or is asked.

**9 · Review, when the card asks for it.** The card ends with « Review
needed » above eight tasks, or when an effect leaves the machine or a
program runs. Then hand the `nika-reviewer` role two things only, the
user's sentence word for word and the path of the file, and nothing of
your design. Where the host has no subagents, answer the reviewer's five
questions yourself from the binary's output (asked versus delivered, the
depth card, effects versus permits, the cost line, what was not verified),
and say in the hand-over that the review was not independent. Below the
threshold, the check and the rehearsal are the review.

**10 · Repair, at most two rounds.** Each finding of the review goes back
with its evidence line; repair, check, review again. After the second
round, stop repairing and hand over with what is left, named.

**11 · Two files, not thirty.** A new project needs the workflow and
`nika.yaml` (one cost ceiling, in the exact shape the authoring skill's
`references/project.md` gives; do not invent keys). If the folder already
has `nika.yaml` or `*.nika` files, add only the new workflow. Run
`nika init` only when the user asks for agent rules or editor settings for
another tool, and say how many files it adds.

**12 · A schedule is read, not switched on.** "Every Monday at 9" becomes a
cron line in the reading, but arming is a separate step (a beat in
`nika.yaml`). Say so, and arm only if the user asks. A scheduled
workflow that keeps a gate pauses at every fire on 0.125.0 (exit 4)
until someone answers: say so before arming, and design the gate out where
the risk allows.

**13 · Hand over.** Two lines on what now exists; one line per craft
addition; one line per upgrade you only offered; the reviewer's verdict in
the reviewer's own words, gaps included; what was not rehearsed and why.
End with the verdict of `nika check` on the final file, quoted (the path,
`clean`, any finding left with its code), then offer `/nika:run`.
