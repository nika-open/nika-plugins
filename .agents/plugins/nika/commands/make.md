---
description: Turn the user's own sentence into a checked workflow — the engine reads the sentence first, with no model call; you write by hand only what the engine could not read
argument-hint: <what the workflow should do, in the user's words>
allowed-tools: Bash(nika check:*), Bash(nika compile:*), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-intent.py *), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-pick-model.sh *), Read, Write, Glob
---

Start from the user's sentence, unchanged: `$ARGUMENTS`. Do not rephrase,
translate or "improve" it before the engine has read it. The engine reads
English and French, and its reading is what the user will check.

**1 · Let the engine read it.** Run
`"${CLAUDE_PLUGIN_ROOT}/scripts/nika-intent.py" "<the sentence>"`.
No model is called and no workflow is written. It prints the pieces of the
sentence, the step each piece became, a schedule down to its cron line, the
questions only the user can answer, and a verdict (exit 0 ready · 2 needs
answers · 3 the engine cannot read this sentence on its own).

**2 · Show the reading.** In the user's language, one line per piece:
their words, then what the workflow does with them. Name any piece that
was left out. This is the moment the user sees that nothing was dropped
and nothing was added.

**3 · Ask only what the engine asks (exit 2).** Put the required questions
in ONE message (use the question tool when there is one). For `model`, run
`"${CLAUDE_PLUGIN_ROOT}/scripts/nika-pick-model.sh"` and propose its
answer; the user confirms. Add no question of your own. Leave the optional
schedule questions alone unless the user wants the schedule switched on.
Never answer a question yourself: a missing address or path is asked, not
guessed.

**4 · Keep it.** Run the helper again with `--answer KEY=VALUE` for each
answer and `--write workflows/<kebab-name>.nika`. Exit 0 writes the file.
If "The model will be told" flags a verb of the request that the
instruction lost, put that verb back in the prompt in the file, then run
`nika check` on it.

**5 · When the engine cannot read the sentence (exit 3).** Write the
workflow by hand with the `nika-authoring` skill. The pieces the helper
listed are your checklist: every piece gets a step, and `permits:` stays at
what the steps really touch. Then tell the user which step covers which
piece, and say plainly that this mapping is yours: the engine did not
check it.

**6 · Two files, not thirty.** A new project needs the workflow and
`nika.yaml` (one cost ceiling, in the exact shape the authoring skill's
`references/project.md` gives; do not invent keys). If the folder already
has `nika.yaml` or `*.nika` files, add only the new workflow. Run
`nika init` only when the user asks for agent rules or editor settings for
another tool, and say how many files it adds.

**7 · A schedule is read, not switched on.** "Every Monday at 9" becomes a
cron line in the reading, but arming is a separate step (a beat in
`nika.yaml`). Say so, and arm only if the user asks.

**8 · Hand over.** Two lines on what now exists, then offer `/nika:run`.
