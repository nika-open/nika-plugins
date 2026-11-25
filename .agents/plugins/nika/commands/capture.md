---
description: Turn the work just done in this conversation into a checked workflow that can run again, showing which step became which task. The workflow is checked, never run
argument-hint: "[which part of the work to keep, in the user's words]"
allowed-tools: Bash(nika check:*), Bash(nika catalog:*), Read, Write, Edit, Glob, Grep
---

Keep what was just done as a workflow the user can run again. Scope:
`$ARGUMENTS` (empty: the most recent piece of work in this conversation).

**1 · List what happened, in order.** Go back through this conversation's
recent work and list:

- the commands that ran, with their arguments;
- the files read;
- the files written or edited, with their paths;
- the model steps: what you judged, summarized, translated or classified
  yourself;
- the hosts touched: the URLs fetched, the APIs called.

Only what happened here: no step you imagine, no host that was not
touched. If « what we just did » could mean two different pieces of work,
ask one question first.

**2 · Map each step to a task, natively.** A URL fetched becomes
`nika:fetch` with the mode that fits; a file read `nika:read`; a search
`nika:grep`; a file listing `nika:glob`; JSON shaping `nika:jq`; a CSV or
YAML conversion `nika:convert`; a file written `nika:write` at the same
path; an edit `nika:edit`. A program with no builtin twin (a test runner,
git) stays an `exec:` with `permits.exec` naming that one program and its
row in the file's exec ledger. Your own
judgement becomes an `infer:` with `schema:` when its output is data and
`max_tokens:` always, on the model the user chooses: ask which, and never
pick a paid model or a seat for them. A value you typed becomes an
`inputs:` entry when it changes from run to run, a `const:` when it does
not. A key or token seen in the conversation never enters the file: it is
a `secrets:` entry naming its store, and you say which variable to set.

**3 · Make it the richest honest version.** The kit ships two guides for this, `capabilities.md` and
`job-anatomy.md`, in the `nika-authoring` skill's `references/` folder where
the plugin is installed. A project where `nika init` ran holds the
references its binary carried, under
`.agents/skills/nika-authoring/references/`: list that folder before you
count on a guide, since a binary can carry fewer of them than the plugin
(0.125.0 writes neither of these two). Without the two guides (the folder
lacks them, or a client only has the MCP server), say so and work from the
oracle instead: `nika catalog --tools` or `nika_tools` for the builtins, and
`nika_examples` for the deep examples (`release-radar`,
`config-drift-sentinel`, `competitor-radar`, `ceo-monday-brief`).
Offer `nika init` for what it gives, the references of the installed binary,
whatever they are, and not as the way to get these two guides; do not run it
unasked, since it writes files in the project.

Add by default what does not widen the effects the conversation had:
validation of what it reads, state between runs when it will repeat,
dedupe, a bounded fan-out where you did items one by one, retry and a
marked degraded result for a dead source, typed schemas, a `nika:assert`
budget, a run report. The effects stay exactly the conversation's: the
same hosts, paths, programs and kind of model. Name in one line each the
upgrades that would widen them (a new send, a new host, paid inference, a
seat route, a new program or MCP server, a write outside those paths);
none is added without the user's yes. Where the work fetched or called an
MCP tool, an addition that needs a new read grant or a new program is an
offer too: it can make `nika check` demand a gate. If check answers
`NIKA-SEC-009` after an addition, take the addition back out and offer it.

**The gate rule** is stated once, in `job-anatomy.md` under « Approve
once, then let it run »: at most one gate, where `nika check` requires
one, before a send (a delivery to a person or an outside destination; the
model the user chose is not one) or before an effect that cannot be undone
(a deletion, a deploy, a payment), and never for cost. So a step of the
conversation that sent something or undid something is kept only if the
user confirms it belongs in every run, and it keeps its gate unless they
say it runs unattended. A scheduled workflow that keeps a gate pauses at
every fire (exit 4) on 0.125.0: say so.

**4 · Write and check, never run.** Write `workflows/<kebab-name>.nika`, or
the path the user names, then run
`nika check workflows/<kebab-name>.nika --json --native-strict` and repair
every finding until it is clean (`nika explain <code>` teaches one). Do
not run the workflow and do not pass `--answer`: running is the next,
separate step (`/nika:run` where the plugin provides it), with its own yes.

**5 · Show the mapping.** One line per conversation step: what happened,
then the task it became. Then the craft additions, the upgrades only
offered, the check verdict, and every step that could not be captured
(a manual decision, an interactive edit) with the reason.
