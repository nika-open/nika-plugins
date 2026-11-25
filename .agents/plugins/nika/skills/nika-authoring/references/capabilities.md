# Capabilities

Read this reference for the matching task; return to [the skill](../SKILL.md) for scope and completion.

Nika is an automation engine, not only a checker. One file can crawl a site,
read a feed, fan out over a hundred items with a bounded pool, keep state
between runs, let a model or an agent application judge, draw a chart or an
image, and hand back a report of what it did and what it cost. Scan this map
before you design a job, then build the richest honest version of it
([job anatomy](job-anatomy.md)).

## Ambition in craft, fidelity in effects

- **Add by default, and name it in the hand-over**, every addition that does
  not widen what the workflow touches: validation of external and model
  values, state between runs (`nika:hash`, `nika:json_diff`,
  `nika:json_merge_patch`), idempotency keys and dedupe, parallel fan-out with
  `max_parallel`, retry and a marked degraded result for a dead source, typed
  schemas with `max_tokens`, `nika:assert` budgets, a `nika:chart`, a run
  report built as a value with the `nika:inspect` cost.
- **Propose in one line, never add in silence**, every addition that widens
  effects: a new send, a new host, new paid inference, a seat route, a new
  program (`exec:`), a new MCP server, a new write outside the folder the
  person named.
- **Interrupt the person as little as possible**: at most one human gate, on
  the grounds the gate rule gives ([job anatomy](job-anatomy.md), « Approve
  once, then let it run »), and a cost assertion instead of a gate when the
  risk is cost.

A craft addition can bring a gate with it. In a job that fetches or calls an
MCP tool, an addition that needs a new `fs.read` entry (state, a read-back, a
config file) or a new program completes the lethal trifecta, and check then
requires a root gate that asks at every run ([job anatomy](job-anatomy.md),
« When an addition brings a gate »). Offer that addition instead of adding it,
and if one you added makes check demand a gate, take it back out.

## How to read the map

One row per capability: the exact field or builtin, when to reach for it, and
the example that shows it. Read an example with `nika try <slug>` or the MCP
`nika_examples` tool; a section name such as « spec 02 §Harness images » is
in the published specification. Names come from `nika catalog --tools`,
`nika spec --schema` and `nika --help`; read argument contracts from
`nika catalog --tools --json` before a call, never from this page.

## Sources

| Field or builtin | Reach for it when | Shown in |
|---|---|---|
| `nika:fetch` (default `mode: markdown`) | a page should arrive as readable text | `05-fetch-chain` |
| `nika:fetch` `mode: article` | you want the prose of a page without its navigation | `competitor-radar` |
| `nika:fetch` `mode: feed` | RSS or Atom entries should arrive as data | `release-radar` |
| `nika:fetch` `mode: sitemap` | the site says which pages changed, with `lastmod` | `competitor-radar` |
| `nika:fetch` `mode: metadata` | a link needs its title, description and preview | `bookmark-triage` |
| `nika:fetch` `mode: jq` with `jq:` | a JSON API answers more than you need | `price-watch` |
| `nika:fetch` `mode: raw` | the exact bytes matter (hash them before parsing) | `config-drift-sentinel` |
| `nika:fetch` `mode: links`, `text`, `selector` with `selector:` | the links of a page, plain text, one CSS-selected region | stdlib extract modes |
| `nika:fetch` `traverse: { max_pages, respect_robots }` | a bounded same-origin crawl (1 to 25 pages, robots honored) returning page digests | stdlib §`nika:fetch` |
| `nika:fetch` `response: { accept: [200, 404] }` | a status is an answer, not a failure (a health probe) | stdlib §`nika:fetch` |
| `nika:fetch` `method:`, `headers:`, `body:`, `form:`, `multipart:` | an API call, a form post, a file upload (a send: propose it) | stdlib §`nika:fetch` |
| `nika:read`, `nika:glob`, `nika:grep` | local files, a folder of them, a search across them | `image-fx-batch` |
| `exec:` with `permits.exec: [<program>]` | a program has no builtin twin (git, a test runner) | `standup-digest` |
| `invoke: { tool: "mcp:<server>/<tool>" }` | an MCP server already wraps the service (a database, a browser) | « MCP servers » below |
| a beat with `cadence: on-webhook`, or `nika serve --bind` (`POST /v1/jobs`) | something outside the machine starts the run | [project](project.md) |

## Data

| Field or builtin | Reach for it when | Shown in |
|---|---|---|
| `nika:jq` | reshape, filter, join, group, sort, zip: the one data language | `25-aggregate-by-key` |
| `extract:` | name jq bindings on a verb's raw response (`tasks.<id>.<name>`) | `05-fetch-chain` |
| `nika:convert` | CSV, YAML or TOML must become JSON, or the reverse | `csv-chart-report` |
| `nika:validate` | an external or model value must fit a JSON Schema before it is used | `19-validate-records` |
| `nika:assert` | the run must stop when a CEL condition is false: a bound, an invariant, a budget | `18-bounded-batch` |
| `nika:json_diff` | what changed since last time, as RFC 6902 operations | `release-radar` |
| `nika:json_merge_patch` | sanctioned overrides apply to a baseline (RFC 7396) | `config-drift-sentinel` |
| `nika:hash` | a fingerprint for dedupe, change detection or an idempotency key | `config-drift-sentinel` |
| `nika:date` | now, a window (« the last 7 days »), formatting, a difference | `competitor-radar` |
| `nika:uuid` | a record you create needs a fresh identifier | `support-triage` |
| `nika:edit` | a literal find and replace inside one file | `release-notes` |
| `nika:emit`, `nika:log` | a machine event in the journal, a line for the person | `config-drift-sentinel` |

## Decisions

| Field or builtin | Reach for it when | Shown in |
|---|---|---|
| `when:` | a task runs only if the data says so (a quiet run spends nothing) | `price-watch` |
| `after: { <task>: success \| failure \| skipped \| terminal \| unwind }` | order without data: a failure route, an always-run step, cleanup | `12-failure-routing` |
| `on_error: { recover \| skip, on_codes }` | a known failure becomes a value and the run goes on | `24-recover-optional-file` |
| `retry: { max_attempts, backoff_strategy, jitter, on_codes }` | a source or a model fails transiently | `competitor-radar` |
| `timeout:` | a slow host must not stall the run (per attempt) | `competitor-radar` |
| `for_each: { items, max_parallel, max_items, fail_fast }` | the same step for every item, with a bounded pool | `07-for-each-locales` |
| `group:` with `${{ group.<name> }}` | fold several parallel legs with one binding | spec 03 §group |
| `nika:decide` | a scored, auditable decision from evidence and a Decision Bundle | `14-decide-publish` |
| `nika:prompt` `mode: confirm \| input \| choice` | the one human decision of the run | `release-train` |

## Models and seats

| Field or builtin | Reach for it when | Shown in |
|---|---|---|
| `model: <provider>/<name>` on the envelope, or inside one task's `infer:` or `agent:` | choose who answers; a `model:` set directly on a task is refused (`NIKA-PARSE-005`); `nika catalog` lists the providers | `01-hello` |
| `ollama/…`, `lmstudio/…`, `llamacpp/…`, `localai/…`, `vllm/…` | the data must stay on the machine (`nika model` manages local models) | `contract-guard` |
| `infer:` with `schema:` and `max_tokens:` | a model answer is data, with a ceiling the checker can price | `04-schema-retry` |
| `returns:` | a task's typed output contract | `09-returns-typed-door` |
| `infer.vision:` | images are an input to the model | spec 02 §Vision inputs |
| `agent:` with `tools:`, `max_turns:`, `max_tokens_total:`, `nika:done` | open-ended work in a bounded loop | `06-code-review` |
| `agent.skills:` | the loop should follow a `SKILL.md` | spec 02 §Agent Skills |
| `for_each` over `agent:` | one read-only reviewer per item | `pr-review-fanout` |
| `run.access: { via, protocol: acp \| api, fallback: none }` | the run must go through an agent application's seat (`codex`, `claude-code`) or a named API route | [seats and images](seats-and-images.md) |
| `run.reasoning: { effort }` | the route offers a native effort the job needs | spec 01 §run |
| `agent.images: { save }` | keep the images a seat draws during its turn | [seats and images](seats-and-images.md) |

## Media

| Field or builtin | Reach for it when | Shown in |
|---|---|---|
| `nika:image_generate` `mode: generate` | images from a brief (local, openai, gemini, xai, mock providers) | `og-images` |
| `nika:image_generate` `mode: edit` with `image:` or `images:` | an existing picture must change | stdlib §`nika:image_generate` |
| `nika:image_fx` | deterministic effects: halftone, duotone, dither, pixelate, grain… | `image-fx-batch` |
| `nika:image_compose` | a contact sheet, a grid, a row or a column of images | `image-compose-sheet` |
| `nika:chart` | rows become an SVG chart: bar, line, area_band, scatter, heatmap | `csv-chart-report` |
| `nika:tts_generate` | text becomes an audio file | `17-tts-self` |
| `agent.images` on a seat | the agent application's own image tool draws it | [seats and images](seats-and-images.md) |

## State and memory

| Field or builtin | Reach for it when | Shown in |
|---|---|---|
| a state file: `nika:read` with an `on_codes` recover, `nika:json_diff`, `nika:write` `overwrite: true` | a repeated job reports only what is new | `release-radar` |
| `nika:hash` of the content | remember what was already seen or sent | `config-drift-sentinel` |
| `outputs:` with `value`, `type`, `description` | the run hands back typed results | `09-returns-typed-door` |
| `.nika/traces/` and `nika trace outputs`, `nika trace peek` | read what a past run produced | [validation](validation-and-execution.md) |

There is no memory builtin in 0.125.0: memory is a file the workflow
reads and writes, inside its declared `fs` boundary.

## Composition

| Field or builtin | Reach for it when | Shown in |
|---|---|---|
| `invoke: { workflow: "./child.nika" }` | a job is too big for one file, or a step is reused | `10-compose-pipeline` |
| a child's `outputs:` | the parent reads what the child returns | `10-compose-child` |
| `invoke: { workflow: "registry:<owner>/<name>@<version>" }` | a pinned published workflow | [composition](composition.md) |
| `nika:compose` (agent loops only) | an agent drafts a workflow and checks it before finishing | `15-compose-self-check` |

## Time

| Field or builtin | Reach for it when | Shown in |
|---|---|---|
| `nika:wait` `duration:` or `until:` | let a system settle, or hold until a window | `incident-war-room` |
| `nika:date` `op: diff` | how long until, how long since | `release-train` |
| `arm:` beats in `nika.yaml` (`cadence`, `plafond`, `manqué`) | the job runs on a schedule; `nika arm` reads, `nika serve` fires | [project](project.md) |

## MCP servers

The builtins cover files, the web, data, media and models. An MCP server
reaches what they do not: a database, a mailbox, a ticket tracker, a
service's own API.

- **The shelf.** The binary carries a shelf of the MCP servers it knows, each
  with its package, the key variable it needs and its pricing class. 0.125.0
  prints no list of it: the server's own documentation gives its
  launch command. A package or a key variable named there is not a way to
  start the server by itself: « The sandbox and the key » below says what
  can start and how a key reaches it.
- **Hubs.** One kind of server is a hub: one server and one key, behind which
  sit many providers. `firecrawl` is on the 0.125.0 shelf (package
  `firecrawl-mcp`, key `FIRECRAWL_API_KEY`, freemium): web search, scrape,
  crawl and its data-provider discovery. No builtin runs a web search, and
  `traverse` crawls 25 pages at most; a hub reaches further, on its own
  account.
- **The call.** A task calls a tool as `invoke: { tool: "mcp:<server>/<tool>",
  args: { ... } }`, granted in `permits.tools` by its exact name or by
  `"mcp:<server>/*"`. The tool's structured answer is the task's typed output.
  An `agent:` whose `tools:` names an `mcp:` glob is offered those tools.
- **Declaration.** The server is declared in the project's
  `.nika/mcp_servers.json`, under the `servers` key:
  `{"mcp_servers_format": 1, "servers": {"<name>": {"command": "…", "args": […]}}}`.
  Each server has one stdio `command` with `args`, and a `network` arm:
  absent denies, `"allow"`, or `{ "allowlist": [hosts] }`. A workflow naming an undeclared server fails
  check `NIKA-INVOKE-001`; a declared one draws the `[mcp-pins]` hint until it
  is approved.
- **Pinning.** `nika mcp approve <server>` starts the server once, prints its
  tools and pins their definitions in `.nika/mcp_pins.json`. A run refuses an
  unapproved tool (`NIKA-MCP-006`) and a tool whose definition drifted
  (`NIKA-MCP-003`). Approving is the person's review of what a model may
  call: show them the command, they run it.
- **Roles.** `permits:` cannot see what a tool reads or sends on its server,
  so the person declares it at approval: `--reads-private <tool>`,
  `--sends-out <tool>`, `--no-role <tool>`. The lethal-trifecta row of check
  counts those roles; a tool with no role is unknown, not safe, and check
  says so with an `[mcp-roles]` hint.
- **The sandbox and the key.** Measured on 0.125.0 with `nika mcp approve`:
  a declared server starts inside a sandbox. It reads and writes inside the
  project folder only, the network is denied unless the `network` arm grants
  it, and its environment is reduced to `HOME`, `PATH` and `PWD`. A launcher
  that resolves or installs the server outside the project when it starts
  fails there: install the server inside the project. The declaration has
  no field that points at a secret store, so a key reaches the server
  through its launch arguments (the value is then written in the
  declaration, copied into the pin file and shown in the process list) or
  through a file inside the project that the server reads (readable by
  whatever is granted that path, committed unless ignored). Each exposes
  the key: the person chooses one, or refuses. Never write its value
  yourself.
- **Cost.** The engine does not price a call to an MCP tool, so
  `--max-cost-usd` does not bound what the service bills. Bound a fan-out
  over a billed tool yourself (`for_each.max_items`, a small `max_parallel`)
  and say so once before the first run.
- **An upgrade that widens effects.** Adding a server or a hub to a workflow
  starts a new process, reaches new hosts and can spend on a paid account.
  Offer it in one line, with what it reaches and what it may cost, and add it
  only on a yes. `nika test` keeps every `mcp:` tool refused.

## Serving and evidence

| Field or builtin | Reach for it when | Shown in |
|---|---|---|
| `nika:inspect` `view: cost \| records \| dag_info \| threads` | the run reports on itself (spend, task states) | `16-inspect-self` |
| `nika serve` (`--once`, `--dry`, `--bind`) | a resident fires the beats, or accepts jobs over authenticated HTTP | [project](project.md) |
| `nika run --resume <trace> --answer <task>=<value>` | a paused gate continues with the person's answer | [decisions](decisions-and-effects.md) |
| `nika trace verify`, `nika trace evidence` | prove what a run did, or export its dossier | [validation](validation-and-execution.md) |
| `nika sign`, `nika key`, `nika run --require-signature` | bind a file to its author, seal runs | [validation](validation-and-execution.md) |
| `nika test` with `<file>.golden.json` | pin the typed outputs of a hermetic workflow | `18-bounded-batch` |
| `run: { entropy: { seeded: <n> }, clock: virtual }` | two runs must produce the same journal | spec 01 §run |
