---
description: Read this project and propose five ambitious workflows that fit it, each mapped to the Nika capabilities it uses, with its design and its one gate if any. Nothing is written until the user picks one
argument-hint: "[a focus, in the user's words]"
allowed-tools: Bash(nika list:*), Bash(nika catalog:*), Read, Glob, Grep
---

Propose the workflows this project would actually use. Focus:
`$ARGUMENTS` (empty: the whole project). This command reads and proposes.
It writes no file, runs nothing, and spends no model call on the project's
data.

**1 · Read the project, read-only.** Look for what already repeats, or
should:

- scripts (`scripts/`, `bin/`, shell and Python entry points), the
  `Makefile` targets, the `scripts` of `package.json`, a `justfile` or
  `Taskfile`;
- CI files (`.github/workflows/`, `.gitlab-ci.yml`, other CI configs),
  above all their scheduled jobs;
- cron and launchd files (a crontab kept in the repository, `*.plist`
  agents), the beats of an existing `nika.yaml`, the workflows `nika list`
  finds;
- data folders (CSV, JSON, exports, fixtures), docs (`docs/`, the README,
  the changelog), content (posts, locales, images).

Read names and headers first; open a file only when it decides an idea.
Never open `.env` or credential files, never quote a secret, and never run
the project's scripts.

**2 · Scan what Nika can do.** The kit ships two guides for this, `capabilities.md` and
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

Prefer the
jobs where a workflow is the right tool: a fan-out over many items (pages,
locales, files, images, tickets), a media pipeline, the same input
compared across several models, parallel agent seats over many items,
crawling and research, a watcher that acts on change, an exact
reconciliation (jq, not model arithmetic), anything that must run again,
be audited or be capped. Skip one-shot questions and code edits.

**3 · Propose five.** For each idea, in the user's language:

- a name, and one sentence on what it does for them;
- the evidence: the file in this project it builds on (the script it
  replaces, the CI job it watches, the folder it reads);
- a one-paragraph design: the phases (gather, normalize, judge, act,
  report), the builtins and fields each phase uses, the branch points,
  the state kept between runs, the run report;
- the capabilities it uses, by exact name (`nika:fetch` `mode: feed`,
  `for_each` with `max_parallel`, `nika:json_diff`, `nika:chart` …);
- its effects: what it reads, the hosts it reaches, what it writes, the
  model it needs (local, paid, or a seat), and its one gate if any;
- its cost: how many model calls a run makes and with which ceiling; the
  estimate itself comes from `nika check` once the file exists.

Make the five different jobs, not five versions of one. At least one runs
with no model at all; at least one reaches past the obvious (media, a
crawl, seats in parallel, a model comparison) when the project gives it
something to work on. Rank them by usefulness.

**The gate rule** is stated once, in `job-anatomy.md` under « Approve
once, then let it run »: at most one gate, where `nika check` requires
one, before a send (a delivery to a person or an outside destination; the
model the user chose is not one) or before an effect that cannot be undone
(a deletion, a deploy, a payment), and never for cost. Say for each idea
whether it would keep a gate: a scheduled workflow that does pauses at
every fire (exit 4) on 0.125.0.

**4 · Write nothing until they pick.** End with one question: which one to
build, if any. On a pick, pass the idea's one-sentence description to
`/nika:make` where the plugin provides it, and say that this sentence is
yours, so they can reword it; elsewhere follow the `nika-authoring` skill's
design steps with the design above. The effects the idea needs beyond what
the user already said (a send, a new host, paid inference, a seat route)
are named again before any file is written.
