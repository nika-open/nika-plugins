---
name: nika-authoring
description: Author, check and repair Nika projects (.nika workflows, the nika.yaml project file and its beats, supporting files, child workflows) and static NIKA findings. Use migration for existing automation ports and debugging for run failures.
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-facts.sh *), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/nika-card.py *), Bash(${CLAUDE_PLUGIN_ROOT}/bin/nika-kit *)
---

# Authoring Nika workflows

Deliver a workflow that expresses the requested inputs, outputs and effects,
with a clean check of the exact final file. Continue through diagnosis and
repair within the user's scope; include execution and artifact inspection when
requested and authorized. If blocked, return the artifact and concrete finding,
not a claim of readiness. These instructions apply across models and clients;
installed engine capabilities and host tools determine what is available.

## Names come from the binary

Builtins, model routes and fields change between releases, and a name from
memory is how a file ends up refused. In the plugin, the line below runs when
this skill loads and prints what this binary serves. If no list of names
follows it (the host does not run it, a policy disabled it, or this copy
lives outside the plugin), read the same names yourself before writing one:
`nika catalog --tools`, `nika catalog`, `nika spec --canon`, or the oracle's
`nika_tools`, `nika_catalog` and `nika_canon`.

!`"${CLAUDE_PLUGIN_ROOT}/scripts/nika-facts.sh" || true`

## Start from the task

The unit of work is the project: its workflows, the optional `nika.yaml`
(name, ceiling, beats, trace and registry policy), the files the workflows
read and the child workflows they call. Check every file you touch, from the
project root ([Project](references/project.md)).

For a small edit, inspect the named file and affected dependencies. For a new
job, `nika list` lists candidates; it does not certify them. Use
`nika explain <candidate>` to understand an existing owner before creating a
replacement. `nika try` and `nika compile --list` expose examples and templates when
an unfamiliar structure needs one. Read the relevant example, not a fixed quota.
Use `nika --version` and the installed schema/catalog for exact names; preserve
the user's model and do not invent an identifier from a marketing name.

Use what the person already gave, what the project keeps and what they
delegated to you. Ask, in one question, only for the facts still missing that
change the result or an effect
([Decisions and effects](references/decisions-and-effects.md)). One scoped
instruction covers each effect it names (saving, running, activating a beat)
once: carry it out without asking again.

**What needs the person, and what never does.** Their yes is needed for the
plan of a new job (once), the answer to a human gate, an effect they did not
name (a send, a host, a program, an MCP server, a write outside their
folder), a paid model route, and publishing anything. Nothing else waits for
them: checking, repairing a finding, adding validation, state or a report,
writing the workflow and what it produces under the project's `out/`, a
rehearsal on the mock model of a job that sends nothing, reaches no host and
pins no model on a task (a pinned model is called for real even under
`--model mock/echo`), and `nika run <file> --dry-run` of any job (the plan,
no effect). Do the
second list without asking, and never the first without a yes.

## Design before you write

Nika is an automation engine: crawls and feeds, bounded fan-outs, state
between runs, seats and their images, charts and media, schedules. For a new
job, or one the person wants to grow, design before the first line:

1. Scan the [capability map](references/capabilities.md) for every source,
   data step, decision, medium and output the job could use.
2. Write a short design: the phases (gather, normalize, judge, act, report),
   the builtins each phase uses, the branch points, the state kept between
   runs, the run report, and the gate if the check will require one.
3. Build the richest honest version of it
   ([job anatomy](references/job-anatomy.md)). **Ambition in craft, fidelity
   in effects**: additions that do not widen what the workflow touches
   (validation of external and model values, state between runs, dedupe and
   idempotency keys, bounded fan-out, retry and a marked degraded result for
   a dead source, typed schemas with `max_tokens`, `nika:assert` budgets, a
   chart, a run report with its `nika:inspect` cost) go in by default and are
   named in the hand-over. Additions that widen effects (a new send, a new
   host, new paid inference, a seat route, a new program or MCP server, a
   write outside the person's folder) are proposed in one line and added only
   on a yes. So is a craft addition that would make check demand a gate.
4. Interrupt the person as little as possible: at most one human gate, on the
   grounds the gate rule gives
   ([job anatomy](references/job-anatomy.md), « Approve once, then let it
   run »), and a cost assertion instead of a gate when the risk is cost.
5. Show the plan and take one yes for the whole job: the phases, then what
   the job reads, writes in the project, sends out of the machine, spends
   and runs, and its cost per run. Those lines come from `nika check` and
   `nika inspect` on a first version of the file, never from reading it by
   eye (in the plugin, `scripts/nika-card.py <file> --plan` prints them).
   Three answers: build, revise, drop.
6. Build by phase: write one phase, `nika check`, repair, then the next. A
   finding met on three tasks has one cause; met on twenty it has several.
7. Have it reviewed cold when it has more than eight tasks or an effect that
   leaves the machine: a reviewer that received only the person's sentence
   and the file path (the `nika-reviewer` role where the host has subagents)
   returns asked versus delivered, depth, effects versus permits, the cost
   line and what it could not verify. With no second agent, answer those
   five questions from the binary's output and say the review was not
   independent. Repair what it finds, for two rounds at most.
8. Before handing over, run the thin-workflow checklist and report the counts.

A small edit to an existing workflow keeps its scope and skips the design.

## Read the reference that resolves the uncertainty

| Task | Reference |
|---|---|
| What Nika can do: every source, data step, decision, model route, medium and schedule, with the example that shows it | [Capabilities](references/capabilities.md) |
| The phases of a real job, the depth bar, the patterns (state, idempotency, validation, budget, run report, fan-out, recover, the always-run report, approve once and the single gate) and the thin-workflow checklist | [Job anatomy](references/job-anatomy.md) |
| A refusal or a surprise that is the engine's, not your file's: secret taint, expression and field limits, binary downloads, stale files, mock answers, resume, two hints that cannot both clear | [Engine behaviors](references/engine-behaviors.md) |
| A seat route (`run.access`, ACP), images an agent application draws (`agent.images`), seat images versus `nika:image_generate`, what mock can rehearse | [Seats and images](references/seats-and-images.md) |
| Find a local owner or example for a new graph | [Workspace and examples](references/workspace-and-examples.md) |
| Envelope, values, modifiers, verbs, permits or CEL syntax | [Language](references/language.md) |
| Check findings, execution, rehearsal, traces or cost reporting | [Validation and execution](references/validation-and-execution.md) |
| Choose native tools, retain an exec, build JSON or prove deterministic rules | [Native tools and artifacts](references/native-and-artifacts.md) |
| Paid inference, extraction schemas or paid-readiness blockers | [Paid inference](references/paid-inference.md) |
| Which model does which step: the six roles, reading the catalog, the price `nika check` computes, where the data goes, proving a cheaper route | [Routing](references/routing.md) |
| Parent/child calls, containment, child outputs or budgets | [Composition](references/composition.md) |
| A project: `nika.yaml`, beats and their zone, supporting files, children, path bases | [Project](references/project.md) |
| An open value, a human gate, exact identifiers, readback, a refused write, a model step a hint questions | [Decisions and effects](references/decisions-and-effects.md) |

Consult only the needed references. When loaded as a Nika runtime skill, linked
files are not automatically injected: the host must supply an authorized read
tool and read grants, or explicitly supply the required files as context.

## Shared contract

- Envelope: `nika: <id>` and a `tasks:` map, exactly one of `infer`, `exec`,
  `invoke`, `agent` per task. Use `nika spec --schema` and `nika catalog --tools`.
- Values belong in `inputs:`, `const:`, `secrets:`. Bind task data with `with:`;
  `after:` orders without data. Secrets use declared stores and `egress:` sinks.
- `permits:` bounds intended effects. Missing grants mean zero authority
  (`NIKA-AUTH-006`); pure compute declares `permits: {}`. Review
  `nika check <file> --infer-permits` proposals against the requested scope.
  Do not widen grants merely to silence findings. For `lift:` (`law: taint` or
  `law: data-as-code`), read the language reference; a lift grants no permit.
- `nika check <file> --json --native-strict` validates the final candidate.
  Inspect the exit status, `clean`, `native_strict_clean`, composition coverage
  and, before paid inference, `paid_ready`. `--fix` applies mechanical repairs;
  review its diff. `nika explain NIKA-XXXX` teaches an unresolved finding.
- A check is evidence, not permission or proof of effects. Preserve existing
  authorization, caps and human gates. `mock/echo` simulates envelope inference;
  task model pins, tools, writes and network effects remain real.
- The estimate covers output tokens; unknown input billing or local compute
  remains unpriced. Metered caps can overshoot for already admitted calls.

## Finish at the requested outcome

For authoring, report the file, actual check verdict, effect scope and remaining
blockers, with the design, the counts (tasks, distinct builtins, branch points,
state, report, gates), the craft additions you made and the effect upgrades
you only proposed. A thin job says why it is thin. Done means three things:
the check is clean, the job was rehearsed (on the mock model when nothing
leaves the machine and no task pins a model, with `--dry-run` otherwise:
the mock does not replace a pinned model), and every file the rehearsal
wrote was opened and parsed. When the person said not to run it, do not rehearse on the mock model
either: read the plan with `nika run <file> --dry-run`, which executes
nothing, and say in the hand-over that the job was not rehearsed. A review's verdict is passed on in the
reviewer's own words, gaps included. The last lines of every hand-over are
the verdict of `nika check <file> --json --native-strict` on the file as it
now stands, quoted: the path, `clean`, each finding left with its code. Say
this whether or not the host checks the file again on its side. For an authorized run, retain its session and exact trace, read
back what it wrote or created and inspect that against the task's expected
result, and report the exit status and verified evidence tier. Reconcile partial effects before any retry. A golden
is suitable only for the simulated plane that supports the workflow; a green
static check alone proves neither behavior nor parity.
