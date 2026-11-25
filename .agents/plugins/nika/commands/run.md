---
description: Run a .nika workflow the smooth way — a plain verdict, one yes with its ceiling, the run in the background, and any question asked here in the conversation
argument-hint: <file.nika> [key=value ...]
allowed-tools: Bash(nika check:*), Bash(nika run:*), Bash(nika trace:*), Bash(nika explain:*), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-verdict.py *), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-pick-model.sh *), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-pending.py *), Bash(${CLAUDE_PLUGIN_ROOT}/bin/nika-kit *), Read, Glob
---

Run the workflow for a person who should never have to read engine
output. Target: `$ARGUMENTS` (no file? `Glob` for `*.nika` — one match
runs, several ask which).

**What needs the person, and what never does.** Their yes is needed to
start the run with its ceiling (once), to answer a gate, to raise the
ceiling or change the model to a paid one, and to run or resume again a
run that stopped (a request to recover it already is that yes, once).
Checking, reading a trace, repairing a finding and showing a plan with
`--dry-run` never wait for them.

**1 · Say what it will do, in plain words.** Run
`"${CLAUDE_PLUGIN_ROOT}/scripts/nika-verdict.py" <file>` and show its
lines as they are: what it reads, what it can reach, the model, the cost,
whether it asks first, the verdict. If the script is unavailable, build
the same lines yourself from `nika check <file> --json`. Never paste the
raw check output, and keep `NIKA-…` codes out of the message unless the
user asks for the detail.

**2 · Not ready? Fix first.** One sentence per problem, then repair the
file and check again. Do not run a file the check refuses.

**3 · Pick the model for them.** Run
`"${CLAUDE_PLUGIN_ROOT}/scripts/nika-pick-model.sh"`. Exit 0 prints the
flags to add (`--model …` or `--access claude-code`). Exit 1 prints the
ways out: offer them as a short choice, and offer a rehearsal
(`--model mock/echo`) so the user can at least watch the steps. Never
leave the user in front of a provider error.

**4 · One yes, with its ceiling.** Ask once, with the verdict lines above
it: "Run it?" The ceiling is part of the yes, as a number you say: the cap
set for this plugin when the host shows one (the `max_cost_usd` setting,
which the `nika-running` skill prints), else a number at or above the cost
line, unless the person names another. A cost line above the cap is said
before asking: the person raises the ceiling, or the run does not start.
Add it as `--max-cost-usd <n>`, a number and never a placeholder. Calls
already started when the ceiling is crossed still finish and count.

**5 · Start it, and do not make the person watch.**
`nika run <file> --json <flags> [--var key=value ...]`, as its own
command: no pipe and nothing chained after it, because a pipe hides the
exit code and a chained line can be refused as a whole. When the host's
shell tool can run a command in the background and tell you when it ends,
start the run that way, say the ceiling and that you will come back when
it ends or asks something, and go on with what the person asked next.
When it cannot, run it in the foreground. Either way the exit code comes
first when it ends: 0 it settled, 4 it waits for an answer, 2 or 3 it was
refused before anything ran, 1 or 130 it stopped.

**6 · It settled (exit 0).** Read the last `run_settled` line: `status`,
`outputs`, `spend`, `receipt.trace_path`. Reply with the result first, then
one line: what it cost, what was unpriced, and where the record is. Offer
`/nika:report` for a page a person can read.

**7 · It waits (exit 4). Ask the question here, now.** The paused frame
carries the question (`message`), and
`"${CLAUDE_PLUGIN_ROOT}/scripts/nika-pending.py"` prints it with the resume
line. Show the question word for word, with the real destination and cost
from step 1, and wait for the user's own answer. Then resume, repeating
every `--var` you passed:
`nika run <file> <same flags and vars> --resume <trace_path> --answer <task>=<their answer>`.
An answer is accepted for 15 minutes after the pause; when a background
run paused longer ago than that, say that resuming will ask again.
**Never answer a question yourself**: permission to run is not an answer to
a gate. Never pass `--answer` on your own initiative. If this gate stands
on none of the grounds the gate rule gives (the authoring skill's
`references/job-anatomy.md`, « Approve once, then let it run »), say so
after the run and offer to design it out, so the next run does not stop.

**8 · It was refused before anything ran (exit 2 or 3).** No step ran,
nothing was paid, and this run left no trace. Do not look for one:
`nika trace outputs` with no trace named reads the latest trace of the
project, which belongs to an older run, and resuming it would continue
that older run. Exit 2 is the file: the findings `nika check` prints, or a
cost floor above the ceiling (repair as in step 2, or ask for a higher
ceiling). Exit 3 is the environment: most often no model route is ready
(`NIKA-1800`, back to step 3). One sentence, the one fix, then run from
the start.

**9 · It stopped (exit 1 or 130). Read before any second run.** The run
already had effects: files written, calls paid, maybe something sent. Find
its trace (`receipt.trace_path` on its last line, or `nika trace ls`), then
`nika trace outputs <trace> --json` names the task that stopped and its
code. Say one sentence on what stopped and the one fix; offer the detail
(`nika explain <code>`) instead of printing it. After the repair, check
the file. Running it again repeats or continues effects, so it needs the
person's yes; with it, prefer
`nika run <file> <same flags and vars> --resume <trace>`, which skips what
settled. Do this whether or not the host reminded you to.

**10 · An approval the person gives every time.** After they answered the
same gate of the same workflow more than once, look whether this binary
can remember an approval: `"${CLAUDE_PLUGIN_ROOT}/bin/nika-kit" --has consent`
(without the kit's scripts: `nika consent --help` answers, or it does not). When
it can (exit 0), say so once, in one line, and show them the command its
help prints: they run the grant, you never do. When it cannot, say nothing
and keep asking at each gate.

**Without the kit's scripts** the steps are the same with the binary alone:
the verdict is `nika check <file> --json` retold in plain words, the model
route is one whose `access_plan[].resolved` is true in
`nika check <file> --json --model <provider/model>` (`nika catalog` lists
the providers the binary knows, not the ones that have a key here), and a
waiting run is listed by `nika trace ls`, its question read from the paused
frame of its trace.
