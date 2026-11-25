---
description: Read the recorded runs of one workflow and propose what they prove could be better — cheaper, steadier, tighter — one change at a time, never an effect
argument-hint: <file.nika>
allowed-tools: Bash(nika check:*), Bash(nika inspect:*), Bash(nika trace:*), Bash(nika catalog:*), Bash(nika run:*), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-improve.py *), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-card.py *), Read, Edit, Glob
---

A workflow that has run a few times has left evidence of where it wastes
money or wobbles. Read that evidence before changing anything. Target:
`$ARGUMENTS`.

**1 · Let the script read the runs.** From the project folder, run
`"${CLAUDE_PLUGIN_ROOT}/scripts/nika-improve.py" <file>`. It reads the
workflow's own traces and prints only what it can prove, each observation
with its evidence line: a step a cheaper model route may do, a step that
was retried or recovered, an output ceiling that cut an answer or sits far
above every answer, a fan-out that pays the same long prompt prefix for
every item, a branch no run ever took, the step that carries most of the
spend. Exit 3 means there is no recorded run of this workflow yet: say so
and stop, since there is nothing to prove. Mock rehearsals are left out of
the cost lines.

Without the kit's scripts, read the runs yourself (`nika trace ls`, then
`nika trace outputs <trace> --json` for each run of this workflow) and keep
to the same rule: an observation needs a line of evidence from a record or
from the file. The card of step 3 is then `nika check <file> --json` read
beside `nika inspect <file> --format json`, compared before and after the
edit.

**2 · Show the observations as they are.** Each with its evidence, in the
person's language. Add none the script did not print; « I think this
prompt is long » is an opinion, and this command deals in evidence. If the
script printed nothing, say that this is not proof the workflow is as good
as it can be.

**3 · One change at a time.** For the observation the person picks (or the
first, when they said to go ahead):

- remember the card first:
  `"${CLAUDE_PLUGIN_ROOT}/scripts/nika-card.py" <file> --plan`;
- make the one edit, keeping the old lines in your reply so it can be put
  back;
- `nika check <file> --json --native-strict`, then rehearse as the job
  allows: on the mock model only when nothing leaves the machine and no
  task pins a model, `--dry-run` otherwise. A model pinned on a task is
  called for real, and billed, under `--model mock/echo`, so after an edit
  that pins one the rehearsal is `--dry-run`, never a mock run;
- `"${CLAUDE_PLUGIN_ROOT}/scripts/nika-card.py" <file> --since-plan`: exit 4
  means the edit added an effect. Take it back out, unless it is the model
  route the person just said yes to (a pin shows as « spends » and
  « called even on a mock run »).

Then the next observation. A change that did not help comes back out.

**4 · What this command never does.** It never changes what the workflow
reads, writes, reaches or sends, never removes a gate and never raises a
ceiling on its own. A cheaper model route stays a proposal until a run on
real data passes the same validation as before: a paid route, and a run on
real data, are the person's yes (the authoring skill's
`references/routing.md` gives the method for choosing one).

**5 · Hand over.** One line per change kept, with the evidence that
prompted it; one line per change put back; what is still only a proposal.
End with the verdict of `nika check` on the final file, quoted.
