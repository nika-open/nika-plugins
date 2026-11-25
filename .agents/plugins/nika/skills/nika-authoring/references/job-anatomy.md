# Job anatomy

Read this reference for the matching task; return to [the skill](../SKILL.md) for scope and completion.

A real job is not « read, ask a model, write ». It gathers from its sources,
makes the data trustworthy, decides what deserves attention, acts only on
that, and says what it did. Write the design first, then build the richest
honest version: craft additions by default, effect additions only when the
person accepts them ([capabilities](capabilities.md)).

## The five phases

| Phase | What it does | Typical builtins |
|---|---|---|
| Gather | read every source, in parallel when they are independent; a dead source fails the run when it is the only one, and degrades it, marked, when it is one of several | `nika:fetch` modes, `nika:read`, `nika:glob`, `nika:grep`, `exec:`, `mcp:` |
| Normalize | turn text into typed data and refuse what does not fit | `nika:convert`, `nika:jq`, `extract:`, `nika:validate`, `nika:assert`, `nika:hash`, `nika:date` |
| Judge | decide what matters: compare with last run, apply laws, let a model judge only what needs language | `nika:json_diff`, `when:`, `nika:decide`, `infer:` with `schema:` and `max_tokens:`, a bounded `agent:` |
| Act | write, edit, draw, send, each effect gated on the data that justifies it | `nika:write`, `nika:edit`, `nika:chart`, `nika:image_generate`, `nika:notify` |
| Report | build the run report as a value, write it, return it | `nika:inspect` `view: cost`, `nika:jq`, `nika:write`, `nika:emit`, `outputs:` |

## The depth bar

Before handing a job over, it clears this bar or the hand-over says why not:

- **Real steps.** Each task changes data or makes a decision. A task that only
  logs is not a step.
- **Branch points.** At least one `when:` that skips work on a quiet run, and
  a failure route: an `on_error:` with `on_codes`, or an `after: { <task>: failure }`.
- **A join.** At least one task binds two or more upstream outputs, or folds a
  `group:`.
- **Every phase present.** A job that validates what it reads, keeps state
  and reports its run ends up calling many builtins; one that calls three is
  usually missing a phase. Name the missing phase and add it, or say why it
  does not apply. The count is a symptom to read, never a number to reach: a
  task added to raise it is padding.
- **State** when the job repeats: it reports what is new since the last run
  (offered, not added, where it would bring a gate: « When an addition
  brings a gate »).
- **A run report**: what was read, what was decided, what was written, what it
  cost, and whether a source was missing.
- **At most one human gate**, on a ground « Approve once, then let it run »
  names, and none otherwise.

Calibrate on the deep examples: `release-radar` (state and a root gate),
`config-drift-sentinel` (fingerprint, merge patch, diff, triage),
`competitor-radar` (date window, bounded fan-out, zip join), `ceo-monday-brief`
(three-branch gather, one gate, capped synthesis).

## Patterns

Each snippet comes from the named example, trimmed to the pattern; the
idempotency and run-report snippets are compositions measured on the engine.
Every one was checked inside a complete workflow. Read the example for the
envelope around it.

### State between runs

From `release-radar`. One path on both sides: the same literal is in
`fs.read` and `fs.write`.

```yaml
  previous:
    invoke:
      tool: "nika:read"
      args: { path: "${{ const.state_path }}" }
    on_error:
      on_codes: [NIKA-BUILTIN-READ-001]   # not-found only: the first run has no state yet
      recover: []
  previous_parsed:
    with: { previous: "${{ tasks.previous.output }}" }
    invoke:
      tool: "nika:jq"   # a read returns a string: parse it, keep the first-run []
      args: { input: "${{ with.previous }}", expression: 'if type == "string" then fromjson else . end' }
  fresh:
    with:
      previous: ${{ tasks.previous_parsed.output }}
      entries: ${{ tasks.feed.entries }}
    invoke:
      tool: "nika:json_diff"   # RFC 6902: the additions are what is new
      args: { before: "${{ with.previous }}", after: "${{ with.entries }}" }
  save_state:
    with: { entries: "${{ tasks.feed.entries }}" }
    after: { fresh: success }
    invoke:
      tool: "nika:write"
      args: { path: "${{ const.state_path }}", content: "${{ with.entries }}", create_dirs: true, overwrite: true }
```

Keep the state file in the folder the person named for output; when they
named none, propose its path in one line. In a job that fetches, the state
read brings a gate with it: offer state there instead of adding it (next
section).

### When an addition brings a gate

Check judges the lethal trifecta from the grants, not from intent. Three legs:
a private read (`permits.fs.read` is not empty), outside content (a
`nika:fetch` or an `mcp:` tool that a task calls) and a way out
(`permits.net.http` is not empty, a write outside the project, or
`permits.exec`). When all three hold, every task the outside content reaches
needs a gate above it, and check refuses the file `NIKA-SEC-009` until one
stands at the root. Measured on 0.125.0:

| The job already | The addition | Check |
|---|---|---|
| fetches and writes in the project | a state file, a read-back of its own output, a config file: any new `fs.read` entry, even one no fetched value touches | refused `NIKA-SEC-009` |
| fetches and writes in the project | a program (`permits.exec`), no read | clean: the fetch's host already was the way out |
| calls an `mcp:` tool, reads a local file, writes in the project | a program (`permits.exec`), even one that touches none of the tool's data | refused `NIKA-SEC-009` |
| reads and writes local files only | state, a read-back, validation | clean |

So in a job that fetches or calls an MCP tool, an addition that needs a new
`fs.read` entry or a new program is an offer, not a free craft addition: say
in one line what it adds and that it brings one question at every run. And
when an addition you made turns a clean check into `NIKA-SEC-009`, take the
addition back out and offer it. Repairing that finding with a gate nobody
asked for makes every scheduled fire wait for a person.

### Idempotency and dedupe

A retried `POST`, `PUT`, `PATCH` or `DELETE` must carry an `idempotency-key`
header: without it check refuses the `retry:` (`NIKA-SEC-016`). Derive the key
from the content with `nika:hash`, as `config-drift-sentinel` fingerprints a
response (stdlib §`nika:fetch`, the effect-safe retry law):

```yaml
  key:
    invoke:
      tool: "nika:hash"
      args: { algo: sha256, content: "${{ const.ticket }}" }
  open:
    with: { key: "${{ tasks.key.output }}" }
    retry: { max_attempts: 3, backoff_strategy: exponential }
    invoke:
      tool: "nika:fetch"
      args:
        url: "https://api.example.com/tickets"
        method: POST
        headers: { idempotency-key: "${{ with.key }}" }
        body: "${{ const.ticket }}"
```

Dedupe records before acting on them, and refuse conflicting duplicates
instead of keeping the first (`21-deduplicate-records`):

```yaml
  deduplicate:
    after:
      agree: success
    invoke:
      tool: nika:jq
      args:
        input:
          dataset: ${{ const.dataset }}
          records: ${{ const.records }}
        expression: '{dataset, records: (.records | unique_by(.id))}'
```

### Validation of external and model values

From `24-recover-optional-file`: validate, then assert the verdict, then use
the value. Give every model answer that is data a `schema:` and a
`max_tokens:`; an answer that does not fit fails instead of flowing on.

```yaml
  validate:
    with:
      content: ${{ tasks.read.output }}
    invoke:
      tool: nika:validate
      args:
        data: ${{ with.content }}
        format: json
        schema:
          type: string
          minLength: 1
          maxLength: 4000
  admit:
    with:
      valid: ${{ tasks.validate.output.valid }}
    invoke:
      tool: nika:assert
      args:
        condition: ${{ with.valid }}
        message: Content must be nonempty and at most 4000 characters
```

### Budget assertion

When the risk is cost, assert the bound instead of asking a person. From
`18-bounded-batch`: refuse an oversized batch before any paid call, then fan
out with a pool and a ceiling per item.

```yaml
  process:
    after:
      admit: success
    for_each:
      items: ${{ const.items }}
      max_parallel: 2
      fail_fast: true
    timeout: 30s
    infer:
      prompt: '${{ const.brief }}

        Item: ${{ item }}'
      max_tokens: 2048
      schema:
        type: object
        additionalProperties: false
        required:
        - summary
        properties:
          summary:
            type: string
            minLength: 1
            maxLength: 4000
```

`for_each.max_items` refuses a longer collection before its first item, and
`nika.yaml` `ceiling:` or `--max-cost-usd` caps the run. In a job that
writes, every `nika:assert` carries the advisory `assert-quarantine` hint
(see « Two hints that cannot both clear » in
[engine behaviors](engine-behaviors.md)).

### Run report

Build the report as a value with `nika:inspect` (`16-inspect-self`). Its cost
view is `{ total_usd, by_task, by_provider, metered }`: `metered: false` means
nothing was priced (a local or subscription model), never that it was free.

```yaml
  cost:
    after: { summary: terminal }
    invoke: { tool: "nika:inspect", args: { view: cost } }
  within_budget:
    with: { cost: "${{ tasks.cost.output }}" }
    invoke:
      tool: "nika:assert"
      args: { condition: "${{ with.cost.total_usd <= const.max_usd }}", message: "the run spent more than its budget" }
  report:
    with:
      cost: ${{ tasks.cost.output }}
      summary: ${{ tasks.summary.status }}
    invoke:
      tool: "nika:jq"
      args:
        input: { cost: "${{ with.cost }}", summary: "${{ with.summary }}" }
        expression: "{ spent_usd: .cost.total_usd, metered: .cost.metered, steps: { summary: .summary } }"
```

Return the report in `outputs:`, and write it with `nika:write` inside the
folder the person named (a write elsewhere is an effect to propose). Give the
writer `after: { <last task>: terminal }` so the report survives a failed run
(« The always-run report » below).

### Fan-out and join

From `competitor-radar`: a bounded pool where one dead item yields `null`,
then a join that zips the inputs with the results and drops the failures.
Put the number dropped in the run report (the inputs' `length` minus the
join's), so a run where every page died does not read as a quiet week.

```yaml
  pages:
    with:
      urls: ${{ tasks.recent.output }}
    for_each:
      items: ${{ with.urls }}
      max_parallel: 4
      fail_fast: false
    on_error:
      recover: null
    timeout: "30s"
    retry:
      max_attempts: 3
      backoff_strategy: exponential
      jitter: true
    invoke:
      tool: "nika:fetch"
      args:
        url: "${{ item }}"
        mode: article
  readable:
    with:
      urls: ${{ tasks.recent.output }}
      pages: ${{ tasks.pages.output }}
    invoke:
      tool: "nika:jq"
      args:
        input: ["${{ with.urls }}", "${{ with.pages }}"]
        expression: >-
          transpose
          | map(select(.[1] != null))
          | map({ url: .[0], text: .[1] })
```

### A dead source

A source that failed must not look like a source that answered. Measured on
0.125.0:

- **Retry first.** `retry:` re-attempts a transient failure and gives up at
  once on the rest. A refused connection is transient (measured); the
  stdlib's fetch contract adds a timeout, a 5xx, a 408 and a 429, and leaves
  a 404 out.
- **The only source: let the run fail.** With no `on_error:`, the run exits 1
  and the always-run report (below) names the source that died. For a watcher
  with one feed that is the honest result.
- **One source among several: degrade, and mark it.** Recover to an empty
  sentinel in the RAW shape of the response, so the `extract:` binding runs
  unchanged (recovering the binding's shape instead fails `NIKA-VAR-004`).
  Carry a `degraded` flag out through `extract:`, put it in the run report,
  and close every state write on it.

```yaml
  feed:
    retry: { max_attempts: 2, backoff_strategy: exponential, jitter: true }
    invoke:
      tool: "nika:fetch"
      args: { url: "${{ const.feed_url }}", mode: feed }
    extract:
      entries: "[.items[] | {title, link}]"
      degraded: ".degraded // false"
    on_error:
      on_codes: [NIKA-BUILTIN-FETCH-001]
      recover: { items: [], degraded: true }
  save_state:
    with: { entries: "${{ tasks.feed.entries }}", degraded: "${{ tasks.feed.degraded }}" }
    when: ${{ with.degraded == false }}
    invoke:
      tool: "nika:write"
      args: { path: "./out/state.json", content: "${{ with.entries }}", create_dirs: true, overwrite: true }
```

Against a closed port: the fetch is retried, fails `NIKA-BUILTIN-FETCH-001`
and is recovered; `save_state` is skipped, the state file is not written, the
report carries `degraded: true` and the run exits 0. Three limits:

- `NIKA-BUILTIN-FETCH-001` is the one code of every `nika:fetch` failure: a
  refused connection, a 404 and a body that is not text all carry it.
  `on_codes` keeps a refused permit loud; it cannot tell a dead network from
  a missing page.
- `nika:inspect` `view: records` reports a recovered task as `success`, so a
  run report built from the records alone hides the recovery: the `degraded`
  flag is what tells it. After the run, `nika trace outputs <trace> --json`
  does say `recovered`, with the code.
- Never recover to invented data in a job that compares, keeps state or
  sends: a hard-coded sample is diffed, summarized and saved as if it were
  today's answer. `release-radar` recovers its feed to a sample so that the
  example runs with no network. Read it for the state pattern, not for its
  recovery.

### The always-run report

A failed run moves every file its writers created during that run to
`.nika/quarantine/<trace>/`, whatever failed: a red `nika:assert`, a dead
source, a refused call. A file that existed before the run never moves. The
exception is a writer admitted by an `after:` edge on `failure`, `terminal`
or `unwind`: its file is the point of that path and stays. So the report's
own writer carries `after: { <last task>: terminal }`. A report reached only
through data from such a task is quarantined with the rest (measured).

What the report may bind: a task that failed or was blocked blocks every
reader of its `output`; its `status` passes whether it succeeded or failed.
Its `error` passes only when it failed: binding the `error` of a task that
succeeded blocks the report. Read the outcome of each task from
`nika:inspect` `view: records`.

```yaml
nika: daily-count
permits:
  tools: ["nika:read", "nika:jq", "nika:write", "nika:inspect"]
  fs:
    read: ["./in/data.json"]
    write: ["./out/summary.json", "./out/run-report.json"]
tasks:
  source:
    invoke:
      tool: "nika:read"
      args: { path: "./in/data.json" }
  summary:
    with: { raw: "${{ tasks.source.output }}" }
    invoke:
      tool: "nika:jq"
      args: { input: "${{ with.raw }}", expression: "fromjson | length" }
  save:
    with: { n: "${{ tasks.summary.output }}" }
    invoke:
      tool: "nika:write"
      args: { path: "./out/summary.json", content: "${{ with.n }}", create_dirs: true, overwrite: true }
  records:
    after: { save: terminal }
    invoke: { tool: "nika:inspect", args: { view: records } }
  report:
    after: { save: terminal }
    with:
      source: ${{ tasks.source.status }}
      records: ${{ tasks.records.output }}
    invoke:
      tool: "nika:write"
      args:
        path: "./out/run-report.json"
        content: { source: "${{ with.source }}", records: "${{ with.records }}" }
        create_dirs: true
        overwrite: true
```

Measured: with `./in/data.json` missing, the run exits 1 and
`./out/run-report.json` stays in place, listing `source` as failed and
`summary` and `save` as cancelled; with the file present, both files are
written. Moving `after:` from `report` to `records` alone sends the report to
quarantine.

### Approve once, then let it run

This is the kit's one statement of the gate rule; every other page links
here. The person approved the job when they asked for it, and again when
they chose to schedule it. A question at every step trains them to click
through without reading, so a human gate is the exception. It has three
grounds, and any one is enough:

- **`nika check` requires it** (`NIKA-SEC-009`). Never design around that
  one with a `default:`; either the gate stays or the addition that brought
  it goes (« When an addition brings a gate »).
- **A send.** The run delivers something to a person or to a destination
  outside the machine: a message, a post, an upload, a ticket, a push. The
  model the person chose is not a send: text going to their own model route
  is the job they asked for, and a gate there would ask on every run of
  every job that uses a hosted model. A fetch that only reads is not a send
  either.
- **An effect that cannot be undone.** A deletion, a deploy, a payment.
  Check does not judge this:
  `NIKA-SEC-009` reads the trifecta only, and a workflow that deletes every
  file a glob returns checks clean with no hint (measured on 0.125.0). A
  clean check is never the proof that no gate is needed.

On a send or an irreversible effect the gate is there by default, and only
the person takes it out. When they say that this job sends or deletes
unattended (a scheduled post is the usual case), remove the gate, bound the
effect with a law instead (the exact recipient in `const:`, a `nika:assert`
on the number of files a deletion may touch) and say in the hand-over that
it now runs without asking. Around the rule:

- When a gate is needed, prefer `mode: confirm`: one question that names
  everything the run will do. At most one gate per job.
- Cost is never a gate. Bound it with a `nika:assert` on a computed budget
  (« Budget assertion » above) plus the run ceiling (`--max-cost-usd`, or the
  project's `ceiling:`).
- Reading, validating, and writing a new file in the folder the person named
  are never gated.
- A scheduled workflow (an `arm:` beat) that keeps a gate pauses at every
  fire on 0.125.0 (exit 4) until a person answers. Say so before it is
  armed, and design the gate out where the risk allows: keep state on local
  sources, drop a send the job does not need, or write a draft for the
  person instead of sending it.
- Never answer a gate for the person and never pass `--answer` on your own
  initiative. A paused run is shown to the person with its question, and
  resumed only with their answer: `--resume <trace> --answer <task>=<answer>`.

How check counts a gate, measured on 0.125.0:

- A `mode: confirm` gate counts by its position: it must stand on every path
  to the effect, data edges included, which in practice makes it the root.
  A refused confirm is the value `false`, not an error, so every effect reads
  the answer: `with: { go: ... }` and `when: ${{ with.go == true }}` (check
  raises a `consent` hint on an effect whose reading it cannot prove).
- A `mode: choice` or `mode: input` gate counts only before an effect whose
  `when:` tests its answer (`when: ${{ with.pick == 'send' }}`); the same
  choice gate without that `when:` is refused `NIKA-SEC-009`.
- A `with:` data edge is a path. The gate must sit upstream of every task
  that untrusted content reaches through data, not only of the task that
  writes: a gate placed after a fetch, with a data edge from the fetch
  straight to the write, does not dominate it and is refused.
- State written by one run reaches the next run's reads through the file, so
  the state file holds what the last run fetched. Its read stays behind the
  gate too: the same job with the state read before the gate is refused
  `NIKA-SEC-009`.
- A gate with a `default:` answers itself unattended and is not a gate. A gate
  with `on_error:` or `for_each:` counts before no effect.

### A fetching job that keeps state

State between runs plus a fetch completes the lethal trifecta: the state read
is a private read, the feed is untrusted ingress, `net.http` is egress. Check
refuses that file `NIKA-SEC-009` until one confirm gate stands at the root.
Say it plainly to the person: this job asks once per run, and a scheduled run
waits for them. The gate's answer reaches every effect:

```yaml
nika: release-watch
const:
  releases_feed: "https://github.com/tokio-rs/tokio/releases.atom"
  state_path: "out/release-watch.json"
permits:
  tools: ["nika:prompt", "nika:fetch", "nika:read", "nika:jq", "nika:json_diff", "nika:write"]
  net:
    http: ["github.com"]
  fs:
    read: ["out/release-watch.json"]
    write: ["out/release-watch.json"]
tasks:
  approve:
    invoke:
      tool: "nika:prompt"
      args:
        mode: confirm
        message: "This run reads ${{ const.state_path }}, fetches ${{ const.releases_feed }} and rewrites the state file. Proceed?"
  previous:
    with: { go: "${{ tasks.approve.output }}" }
    when: ${{ with.go == true }}
    invoke:
      tool: "nika:read"
      args: { path: "${{ const.state_path }}" }
    on_error:
      on_codes: [NIKA-BUILTIN-READ-001]
      recover: []
  feed:
    with: { go: "${{ tasks.approve.output }}" }
    when: ${{ with.go == true }}
    invoke:
      tool: "nika:fetch"
      args: { url: "${{ const.releases_feed }}", mode: feed }
    extract:
      entries: "[.items[] | {title, link}]"
  previous_parsed:
    with: { previous: "${{ tasks.previous.output }}" }
    invoke:
      tool: "nika:jq"
      args: { input: "${{ with.previous }}", expression: 'if type == "string" then fromjson else . end' }
  fresh:
    with:
      previous: ${{ tasks.previous_parsed.output }}
      entries: ${{ tasks.feed.entries }}
    invoke:
      tool: "nika:json_diff"
      args: { before: "${{ with.previous }}", after: "${{ with.entries }}" }
  save_state:
    with:
      go: ${{ tasks.approve.output }}
      entries: ${{ tasks.feed.entries }}
    when: ${{ with.go == true }}
    after: { fresh: success }
    invoke:
      tool: "nika:write"
      args: { path: "${{ const.state_path }}", content: "${{ with.entries }}", create_dirs: true, overwrite: true }
outputs:
  new_entries: ${{ tasks.fresh.output }}
```

The same file without `approve` is refused `NIKA-SEC-009`; with it, check is
clean with no hint. `release-radar` is the full version of this job.

That root gate asks before anything is listed: the person approves a run
whose findings they have not seen. The honest alternative is a first,
read-only phase that lists what the run will act on, then the gate the
trifecta requires, then the state phase. The preview cannot say what is new,
because comparing with the state is a private read and stays behind the gate,
and the second fetch can differ from the preview. Say both when you offer it.

```yaml
nika: release-watch-preview
const:
  releases_feed: "https://github.com/tokio-rs/tokio/releases.atom"
  state_path: "out/release-watch.json"
permits:
  tools: ["nika:fetch", "nika:jq", "nika:prompt", "nika:read", "nika:json_diff", "nika:write"]
  net:
    http: ["github.com"]
  fs:
    read: ["out/release-watch.json"]
    write: ["out/release-watch.json"]
tasks:
  preview:
    invoke:
      tool: "nika:fetch"
      args: { url: "${{ const.releases_feed }}", mode: feed }
    extract:
      entries: "[.items[] | {title, link}]"
  listing:
    with: { entries: "${{ tasks.preview.entries }}" }
    invoke:
      tool: "nika:jq"
      args: { input: "${{ with.entries }}", expression: '"\(length) releases in the feed: " + (map(.title) | join(", "))' }
  approve:
    with: { listing: "${{ tasks.listing.output }}" }
    invoke:
      tool: "nika:prompt"
      args:
        mode: confirm
        message: "${{ with.listing }}. Compare them with ${{ const.state_path }} and rewrite that file?"
  feed:
    with: { go: "${{ tasks.approve.output }}" }
    when: ${{ with.go == true }}
    invoke:
      tool: "nika:fetch"
      args: { url: "${{ const.releases_feed }}", mode: feed }
    extract:
      entries: "[.items[] | {title, link}]"
  previous:
    with: { go: "${{ tasks.approve.output }}" }
    when: ${{ with.go == true }}
    invoke:
      tool: "nika:read"
      args: { path: "${{ const.state_path }}" }
    on_error:
      on_codes: [NIKA-BUILTIN-READ-001]
      recover: []
  previous_parsed:
    with: { previous: "${{ tasks.previous.output }}" }
    invoke:
      tool: "nika:jq"
      args: { input: "${{ with.previous }}", expression: 'if type == "string" then fromjson else . end' }
  fresh:
    with:
      previous: ${{ tasks.previous_parsed.output }}
      entries: ${{ tasks.feed.entries }}
    invoke:
      tool: "nika:json_diff"
      args: { before: "${{ with.previous }}", after: "${{ with.entries }}" }
  save_state:
    with:
      go: ${{ tasks.approve.output }}
      entries: ${{ tasks.feed.entries }}
    when: ${{ with.go == true }}
    after: { fresh: success }
    invoke:
      tool: "nika:write"
      args: { path: "${{ const.state_path }}", content: "${{ with.entries }}", create_dirs: true, overwrite: true }
outputs:
  new_entries: ${{ tasks.fresh.output }}
```

Measured: check is clean with no hint. Bind the preview into the question
only: the same file where the write also binds the preview's entries is
refused `NIKA-SEC-009`, since that data edge bypasses the gate. The question
shows text a feed chose; it is displayed to the person, never executed.

## Engine behaviors to design around

Secret taint, the expression subset, field and tool limits, binary
downloads, the stale file a skipped write leaves, what mock answers, resume
and two hints that cannot both clear: each was measured on 0.125.0 and
lives in [engine behaviors](engine-behaviors.md). Read it before you design
around a refusal; none of them is a defect of your file.

## Before handing over: the thin-workflow checklist

Count and report: tasks, distinct builtins, branch points, joins, state, the
report, gates. Then answer each line, or say in the hand-over why it does not
apply:

- [ ] More than three tasks, and more than one phase. A read, infer, write
      chain is the thin shape.
- [ ] Every external value (a file, a page, an API answer, a model answer that
      is data) is validated before an effect or a model uses it.
- [ ] Every `infer:` has `max_tokens:`, and `schema:` when its output is data.
      Every `agent:` has `max_turns:` and `max_tokens_total:`.
- [ ] A quiet run spends nothing: `when:` on `size(...) > 0` before paid work.
- [ ] A repeated job keeps state and reports only what is new (a fetching
      job offers it, since it brings the gate).
- [ ] Every fan-out has `max_parallel`; a batch that must survive one bad item
      has `fail_fast: false` and a `recover:`.
- [ ] Every source that can fail either fails the run or recovers to an
      empty sentinel whose `degraded` flag reaches the report and closes the
      state write. None recovers to invented data.
- [ ] Every retried mutating call carries an `idempotency-key`.
- [ ] A run report exists as a value, written and returned, by a writer with
      `after: { <last task>: terminal }` so a failed run keeps it.
- [ ] Every enum lists its safe value first (mock takes the first).
- [ ] A write behind `when:` either always writes, or removes its stale file
      on the quiet branch.
- [ ] No send's reply feeds a write: the record is gated by `when:` alone.
- [ ] At most one gate, on a ground « Approve once, then let it run » names:
      check requires it, a send, or an effect that cannot be undone. None on
      cost. A scheduled job that keeps its gate is said to pause at every
      fire.
- [ ] No effect the person did not ask for: a new send, host, paid model,
      seat route, program (`exec:`), MCP server or write outside their
      folder is proposed in one line instead. So is a craft addition that
      would bring a gate. A program that stays has its row in the exec
      ledger ([native and artifacts](native-and-artifacts.md)).
- [ ] `nika check <file> --json --native-strict` is clean on the final file,
      or the one finding left is named in the hand-over with the reason it
      cannot clear (a binary download's `native-first/001` is the known
      case, [engine behaviors](engine-behaviors.md)).
