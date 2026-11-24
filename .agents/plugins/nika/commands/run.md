---
description: Run a .nika workflow the smooth way — a plain verdict, one yes, a model chosen for the user, and any question asked here in the conversation
argument-hint: <file.nika> [key=value ...]
allowed-tools: Bash(nika check:*), Bash(nika run:*), Bash(nika trace:*), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-verdict.py *), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-pick-model.sh *), Read, Glob
---

Run the workflow for a person who should never have to read engine
output. Target: `$ARGUMENTS` (no file? `Glob` for `*.nika` — one match
runs, several ask which).

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

**4 · One yes.** Ask once, with the verdict lines above it: "Run it?"
A cap is part of the yes: add `--max-cost-usd <n>` at or above the cost
line, and say the number.

**5 · Run and report the result, not the log.**
`nika run <file> --json <flags> [--var key=value ...]`, as its own
command: no pipe and nothing chained after it, because a pipe hides the
exit code and a chained line can be refused as a whole. Read the last
`run_settled` line: `status`, `outputs`, `spend`, `receipt.trace_path`.
Reply with the result first, then one line: what it cost and where the
record is.

**6 · The run pauses (exit 4)? Ask the question here, now.** The paused
frame carries the question (`message`). Show it with the real
destination and cost from step 1, and wait for the user's own answer.
Then resume, repeating every `--var` you passed:
`nika run <file> <same flags and vars> --resume <trace_path> --answer <task>=<true|false>`.
The answer is only accepted for 15 minutes after the pause, so do not
start other work in between. **Never answer a question yourself**:
permission to run is not an answer to a gate.

**7 · It failed?** One sentence on what stopped and the one fix. Offer
the detail (`nika explain <code>`) instead of printing it.
