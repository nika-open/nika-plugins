<p align="center">
  <img src="./assets/nika-logo.png" alt="Nika" width="96">
</p>

# nika · author AI workflows as checkable files

Teach your agent to hand repeatable work to
[Nika](https://github.com/nika-open/nika): a plain-text
`.nika` workflow it can **check before a token is spent** and
**verify after**. One install adds the full bundle from the
[nika-plugins](https://github.com/nika-open/nika-plugins) marketplace —
your agent learns to author, debug, operate and migrate workflows on its own.

```sh
brew install nika-open/tap/nika   # the binary first; the plugin invokes it

# Claude Code
claude plugin marketplace add nika-open/nika-plugins
claude plugin install nika@nika

# Codex
codex plugin marketplace add nika-open/nika-plugins
codex plugin add nika@nika
```

Cursor, Grok Build and other clients: see
[Install in your client](https://github.com/nika-open/nika-plugins#install-in-your-client).
Without a plugin, `nika init` writes part of this kit into a repository: the
authoring skill, the three hooks, the Cursor rules, three of the five
subagents (author, debugger, migrator) and the oracle wiring.

## What one install gives your agent

| Component | What it does |
|---|---|
| `nika-authoring` skill | a concise authoring entry with task-specific language and validation references |
| routing guide (`references/routing.md`) | a method for choosing which model does which step, with no model name and no price in it: six roles (extract, classify, judge, write, plan, see), how to read `nika catalog`, the price `nika check` computes for a candidate, where the data goes, and how to prove a cheaper route before keeping it. The person's model stays the default and a paid route is theirs to accept |
| `nika-debugging` skill | run forensics: trace ls → show → outputs → verify · resume lines · surgical reruns |
| `nika-operating` skill | day-2 hardening: spend caps · permits · secrets · model swaps · CI goldens · OTLP export |
| `nika-migration` skill | convert scripts, CI jobs and prompt chains to workflows — mapping table + parity protocol |
| `nika-author` subagent | designs, writes phase by phase and repairs the requested artifact, and ends its hand-over with the check's verdict on the file, quoted; launching belongs to the conversation |
| `nika-reviewer` subagent | judges a finished workflow cold: it receives the person's sentence and the file path, nothing of the author's reasons, and returns asked versus delivered, the depth card, effects versus permits, the cost line `nika check` prints and what it could not verify. It edits nothing |
| `nika-scout` subagent | gathers the facts a design needs (files and their shape, existing workflows, catalog lookups, what a past run did) on a small fast model; read-only |
| `nika-debugger` subagent | root-causes a failed or paused run from its hash-chained trace, hands back the exact resume line |
| `nika-migrator` subagent | ports existing automation: inventory → native-first mapping → check loop → golden pin |
| role settings (Claude Code) | every role inherits the session's model, so the choice and the bill stay with the person; only the scout names a cheaper one. Each has an effort level and a turn cap. The author and the debugger keep a small project memory of repairs that worked, project conventions and hosts that flake, never a secret, a data value or a personal detail. Other hosts read the same bodies and ignore the settings they do not know |
| language rule | the 4-verb surface (`infer` · `exec` · `invoke` · `agent`), auto-loaded on `*.nika` |
| delegation rule | teaches the agent WHEN to propose a workflow (repeatable · multi-step · spend-bound AI work) and which bundled surface to reach for |
| `/nika:check` · `/nika:explain` · `/nika:compile` | audit a file · explain a finding code · compile an exact skeleton or conservative edit |
| `/nika:trace` · `/nika:permits` | read a run's flight recorder (verdict · root cause · resume line) · infer and paste the tightest permits boundary |
| `/nika:doctor` | diagnose this machine's Nika surface — binary · installed plugin kits (train drift, per-client fix) · providers · wiring — advisory by design, never breaks automation |
| session-context hook | a workspace with workflows greets the agent with the full nika map at session start (surfaces · laws · where traces live) — Cursor **and** Claude Code dialects |
| check-on-edit hook | every agent edit to a `*.nika` is audited immediately, and an edit to `nika.yaml` gets its shape checked and every beat read by `nika arm`, as the [`nika arm` reference](https://docs.nika.sh/reference/arm) teaches (findings in the hook log; never blocks the edit) |
| guard-run hook | pre-run judgment with findings on refusal (Cursor `beforeShellExecution` · Claude Code `PreToolUse`); installation and availability boundaries below |
| MCP oracle (9 tools) | `nika_check` · `nika_explain` · `nika_schema` · `nika_examples` · `nika_template` · `nika_canon` · `nika_catalog` · `nika_tools` · `nika_inspect` — read-only, by design |
| `nika-running` skill | the smooth path: a plain-words verdict, one yes that carries a spending cap, the run, and the workflow's own questions asked in the conversation |
| `/nika:run` · `/nika:pending` | check, then run with one yes that carries its ceiling, in the background where the host can; a question is shown word for word and answered by the person alone, and a run that stopped is read before any second run · list the runs waiting for an answer |
| `/nika:make` | turn the user's own sentence into a workflow by one loop: the engine reads the sentence first (`nika compile`, no model call), a scout gathers the facts the design depends on, the person approves the plan once (phases, the effect card, the cost per run), the file is built phase by phase with a check after each, a reviewer judges it cold above eight tasks or when an effect leaves the machine, repairs stop after two rounds, and the hand-over ends with the check's verdict, quoted. Craft that widens no effect is added; an effect the sentence did not name is offered |
| approval rule | every page that can stop for the person names what needs their yes (the plan of a new job, the answer to a gate, an effect they did not name, a paid model route, publishing) and what never waits for them (a check, a repair of a finding, added validation, a dry run, a mock rehearsal of a job that sends nothing). A test pins both lists on the commands, the rule, the five skills and the session map |
| `/nika:report` | builds a page a person can read from a run's record: what ran, what was decided at a gate, what was written, what failed, was recovered or was skipped, and what it cost with its unpriced part named. One self-contained HTML file and its Markdown twin, written under the project's `out/` and nowhere else (a link at a target is replaced, never followed), every line read off `nika trace outputs` and the trace's own events, and every string a trace holds printed as one bounded line of data. It offers to publish where the host can, and never publishes on its own |
| `/nika:improve` | reads the recorded runs of one workflow and prints only what a script can prove, each observation with its evidence line: a step a cheaper model route may do, a step retried or recovered, an output ceiling that cut an answer or sits far above every answer, a fan-out that pays the same long prompt for every item, a branch no run took, the step that carries most of the spend. Changes are proposed one at a time, the card is compared before and after each, and no change touches what the workflow reads, writes, reaches or sends. Mock rehearsals are left out of every cost line |
| `/nika:connect` | gives a workflow a tool it lacks: looks at the builtins and the servers the project already declares, finds the MCP server for a service (from the binary's shelf when it prints one, from the server's own documentation otherwise, never from memory), offers it before writing anything, then writes the declaration and the exact tool permits and checks. It states the sandbox a server starts in and the two ways a key can reach it, with what each exposes, and what the spending ceiling does not cover; approving the server's tools stays the person's command |
| `/nika:ideas` · `/nika:capture` | read the project (scripts, CI, schedules, data, docs) and propose five workflows it would use, each mapped to the capabilities it needs, writing nothing until one is picked · turn the work just done in the conversation into a checked workflow, showing which step became which task, never running it. Both are also served as MCP prompts |
| plan card (`scripts/nika-card.py`) | draws what a workflow reads, writes in the project, sends out of the machine, spends and runs, straight from `nika check` and `nika inspect`, and says when a review is needed. `--plan` remembers the card the person approved and `--since-plan` names every effect added after it (exit 4), so an effect added by mistake is caught by a script. It names the models a run on the mock model would still call (a model a task pins), since such a job is read with `--dry-run` and never rehearsed on mock. Recording a plan again replaces it, and the card says so with the effects the earlier plan did not have: the approval itself stays the person's, in the conversation |
| `bin/nika-kit` | the one place that decides which `nika` binary the kit's helpers use: a `NIKA_BIN` pin, then, inside the engine tree only, the session's build under `CARGO_TARGET_DIR` when that folder is absolute and outside the tree, then the PATH's absolute folders. A project never chooses the binary: a build under a tree's own `target/` is never picked, and the default output names it with the pin that selects it. It prints the path, the reason and the version, answers `--has consent` and `--has mcp-shelf` by asking the binary, and says so when the run guard, which judges with the PATH's `nika` on purpose, uses another one |
| facts at skill load (Claude Code) | `nika-authoring` and `nika-running` open with a few lines printed by this machine's binary: its version, its builtins, one model route per provider that resolves, how many runs wait. On other hosts, or where a policy disables it, each skill says which commands print the same names |
| author hand-over gate (Claude Code) | when the `nika-author` role stops, `nika check` runs on every file it wrote or named, inside one time budget, and the role is sent back, at most twice, while findings remain, no file was named or a file could not be reached in that time; a clean pass clears the count, which bounds a loop and is not a security control. A missing binary warns and lets it stop. The role's own last step is the same check, quoted, so the rule holds on hosts without the hook |
| language server (Claude Code) | `nika lsp` wired through `.lsp.json`: the findings of `nika check` reach the agent after each edit, with no process started per edit. Terminal sessions only; the check-on-edit hook covers the rest |
| session-status hook (Claude Code) | says at session start that the binary is missing (the guard then refuses every shell command inside a Nika project and warns once elsewhere), or that a run in the workspace is waiting for an answer |
| intent hook (Claude Code) | a prompt that sounds like a schedule, a batch, "do it again", a fan-out over many pages, locales or images, a model comparison, a watcher or a reconciliation (English and French) gets ONE hint per session; when the engine can read the sentence, the hint already carries its reading (pieces, schedule, questions). Silent otherwise, no model call, and nothing is written in the project |
| stop gate (Claude Code) | a `*.nika` changed during the session that fails `nika check` sends the agent back once, with the reason in plain words; it also catches files written through the shell, which the edit hook and the language server never see. « Changed » means newer than a marker written once, at the first start of the session, so a compaction or a resume does not hide earlier work; each version is checked once, five checks a turn, and files past the fifth are named as not checked. A check that could not run is said as such. The marker sits in a folder the agent can write: the gate catches a forgotten check and is not a defence against the agent it reminds |
| waiting-runs monitor (Claude Code) | prints one line when a run starts waiting for an answer, while the `nika-running` skill is in use; interactive sessions only |
| run-progress monitor (Claude Code) | while the `nika-running` skill is in use: one line when a task fails, is recovered or pauses, and one when metered spend passes half, then nine tenths, of the run's ceiling (read from the trace). A task that succeeds prints nothing; interactive sessions only |
| failed-run hint (Claude Code) | a `nika run` that ends red brings back one reminder: read the trace before any second run, since a run from the start repeats every effect of the first; exit 4 is told apart as a pause the person answers. The running skill states the same rule for hosts without the hook |
| compaction notes (Claude Code) | before a long conversation is summarized, the runs that wait for an answer and the workflows changed in the session are written into the summary, by name only (never the text of a question). On other hosts the skill says to list them again with `nika trace ls` |
| `port-to-nika` workflow (Claude Code) | ports many files at once (n8n exports, scripts), one agent per file, each result checked, with a report of what could not be ported. Written and syntax-checked, not yet run in a session |
| `nika-forge` workflow (Claude Code) | builds one workflow from a plan the person approved: a scout gathers the facts, the author writes phase by phase, the reviewer judges the file from the sentence and the path alone and rehearses what is safe to rehearse, repairs stop after two rounds, and the result carries the path, the check's exit code, the counts and the reviewer's verdict in its own words. It stops with the engine's questions when only the person can answer them, and lists as offers every effect the approved plan did not hold. Written and syntax-checked, not yet run in a session |
| `nika-audit` workflow (Claude Code) | audits every workflow of a folder without running one, one small-model reader per file: the check verdict, permits declared against permits needed, whether the cost has a ceiling, and whether a job reads private data, takes outside content and can send with no question asked. Returns one ranked list; a file that gave no result is listed as not audited, never as clean. Written and syntax-checked, not yet run in a session |
| `evals/` | thirteen cases for `claude plugin eval` (see `evals/README.md`). Seven on the first contact: offered on intent · the engine reads the sentence first · a missing address is asked, never guessed · plain verdict · never answers a question for the user · stays quiet when it has nothing to add · designs a new job deep by default. Six on the loop: reviewed before the hand-over · a gate brought back from a background run · a cheaper route for a mechanical step · a tool offered before anything is written · improvements that cite the recorded runs · never a standing approval created. The last seven are written and their fixtures played on 0.125.0, not yet run in a session |
| `max_cost_usd` setting (Claude Code) | the spending cap the `nika-running` skill and `/nika:run` put on a run unless the user names another one; asked once when the plugin is enabled. Where a host does not fill it in, the ceiling is a number at or above the cost line, never a placeholder |

<p align="center">
  <img src="https://raw.githubusercontent.com/nika-open/nika/main/media/gifs/editor-diagnostics.optimized.gif" alt="The language server's findings in an editor: a squiggle, its explanation, and one keystroke that clears it" width="640">
</p>

## The work it supports

Start from the named workflow or a suitable template, resolve unfamiliar shapes
from the installed catalog, and adapt the artifact to the requested result.
The authoring entry routes to only the needed references. Check the final file,
repair actionable findings, and report concrete blockers if it is not ready.
When execution is requested and authorized, the coordinating agent can run it
within the existing effects and budget, inspect outputs and verify the trace.
A check, run result and integrity verdict are different evidence.

No plugin store to audit on the workflow side either: everything
callable is a tool under `invoke:`, and the engine ships its own
[builtin library](https://docs.nika.sh/reference/builtins).

## Good to know

- **macOS GUI PATH**: Cursor may not inherit your shell PATH — if the
  MCP oracle does not start, launch Cursor from a terminal once
  (`open -a Cursor`) or ensure `nika` is reachable from GUI apps.
- **The hooks take no program from the project.** Hosts start hooks in
  the open project. The kit's manifests, and the wiring `nika init`
  writes, start every hook with `/bin/bash -p`: the host's PATH does not
  pick the shell, and in that mode bash reads no `BASH_ENV` file and
  takes no function from the environment. Before it starts anything,
  each hook and helper keeps only the PATH's absolute entries whose real
  folder lies outside the project, so `nika`, `git`, `python3`, `cat` and
  the rest never come from the repository, whether a relative entry
  (`.`, `bin`, `node_modules/.bin`, an empty one), an absolute one or a
  link names its folder. The project is each of `CLAUDE_PROJECT_DIR`,
  `CURSOR_PROJECT_DIR` and the working folder, with the git work tree
  around each, but never your home or a folder above it, so the PATH
  folders under your home stay usable. `NIKA_BIN` counts only as an
  absolute path. The Python hooks start through `python-hook.sh`, which
  finds `python3` on that PATH and runs the script with `-I` from its
  first line, so `PYTHONHOME`, `PYTHONPATH`, the working folder and the
  user's site folder never decide what it loads; every other Python call
  a hook makes runs with `-I` too, and the kit's scripts start its own
  bash helpers with `bash -p`.
- **What the hooks trust.** The environment a hook starts with is the
  host's to set, and the hooks trust it: they defend against the open
  repository, its files and its folders, not against that environment.
  Each host's rules decide how a hook is started. Cursor runs a plugin's
  hooks from the plugin's folder (`CURSOR_PLUGIN_ROOT`), but `stop` and
  `subagentStop` from the workspace root, where a relative command would
  name a file of the project, so a hook of those two must name its
  script by `"${CURSOR_PLUGIN_ROOT}"/` (the kit has none); it requires
  `version: 1` in the hooks file, and it lets a command through when a
  hook crashes, times out or exits with anything but 2 unless the hook
  sets `failClosed`, which no hook of the kit does
  (<https://cursor.com/docs/hooks>, read 2026-11-26). Codex gives plugin
  hooks `PLUGIN_ROOT` and, as Claude Code does, `CLAUDE_PLUGIN_ROOT`, and
  matches its shell commands as `Bash`, the guard's matcher
  (<https://learn.chatgpt.com/docs/hooks>, read 2026-11-26). Every
  manifest quotes that root: unquoted, a root whose path holds a space
  splits there, and the shell's exit 127 is an error every host lets
  through. Not defended:
  - an absolute PATH folder outside the project that someone else can
    write, a `NIKA_BIN` that names another program, `TMPDIR`, and every
    other variable the host passes;
  - a configuration of the project that sets the environment for later
    hooks (in Cursor, a `sessionStart` hook can return `env` for every
    hook after it): trusting a workspace trusts that configuration;
  - a helper a slash command or an agent starts by its own path
    (`nika-facts.sh`, `nika-card.py` and the others): its shebang finds
    `bash` or `python3` through the PATH it is given before its first
    line runs, a bash started that way honours `BASH_ENV` and imports
    exported functions, and that first Python honours `PYTHONHOME`
    before the script starts itself again with `-I`;
  - a system without `/bin/bash` (NixOS, for one): the manifests' hooks
    cannot start there, and on all three hosts a hook that cannot start
    lets the command through (Claude Code and Codex block only on exit 2,
    Cursor only with `failClosed`, which the kit does not set), so the run
    guard is off; `nika run` itself still refuses a workflow whose
    `nika check` is not clean;
  - the MCP server (`.mcp.json`, `mcp.json`) and the language server
    (`.lsp.json`), which the host starts itself as a bare `nika` through
    its own PATH, with no block of the kit in front.
- **Two hook classes, two failure laws.** The *comfort* hooks (session
  context, check-on-edit) degrade quietly: a missing binary or an
  unreadable file means no context and no verdict, never a bricked
  editor. The *run guard* is the opposite — fail-visible: if its judge
  answers but breaks, or cannot judge the command it was handed, the
  hook blocks the action with exit 2 and `guard_unavailable` on stderr,
  and the message names that cause (a broken binary to check with
  `nika doctor`, or the part of the command the judge could not see).
  The shim cannot prove a command unrelated without the engine's JSON
  and shell decoding: it streams stdin directly into the engine's
  bounded reader and never guesses scope or host dialect. It passes on
  only a whole verdict: one line that ends, at most 16 KiB, holding one
  JSON object whose strings close and whose members hold strings or
  objects (checked with `awk`, which the PATH must hold), and, when the
  judge exits 2, a deny. Anything else (an answer cut short, a second
  line, a banner) is refused like a broken binary. A verdict that denies
  is answered the way its host documents a block whose reason reaches
  the agent (read 2026-11-26). Claude Code takes a blocking hook's
  stderr on exit 2 as the block's message
  (<https://code.claude.com/docs/en/hooks>), and Codex takes exit 2 with
  the blocking reason on stderr (<https://learn.chatgpt.com/docs/hooks>):
  there the hook exits 2 with the verdict and a `guard_denied` line on
  stderr. Cursor blocks on exit 2 but documents no message from it; it
  sends the agent the `agent_message` of a `"permission": "deny"` answer
  on exit 0 (<https://cursor.com/docs/hooks>). So under Cursor
  (`CURSOR_VERSION` set) the hook passes on Cursor's own deny, exactly as
  nika guard writes it (one flat object holding `permission` once, with
  `deny`, beside at most one `agent_message` and one `user_message`, and
  no other key; a word written with an escape never counts as one of
  these), as its answer, with exit 0, and blocks any other deny by exit
  2. A deny in one host's JSON is never handed to another: Claude Code
  finds no decision in Cursor's `"permission":"deny"` and runs the
  command. nika guard answers in Cursor's dialect only for a payload
  without `hook_event_name`, which Cursor's payload carries, so today a
  deny on Cursor is blocked by exit 2 and its reason is not documented to
  reach the agent. Every end of the hook but a passed-on verdict's exit
  0, a caught signal or an unforeseen failure included, is the blocking
  exit 2.
  A judge that has not answered within 20 s is ended, with every
  process it started, and the command is refused the same way (a host
  that times a hook out would let the command through; the kit's
  Claude Code and Cursor wiring give the hook 30 s). The judge reads
  only a regular workflow file of at most 4 MiB; a pipe, a folder or a
  larger file named by `nika run` is refused, never waited on.
  The other deny is a run on a file with
  live check findings: the denial carries the findings, for the agent to
  repair and re-check wherever its host hands the reason over (above).
- **When the `nika` binary is missing from the editor PATH**, the shim
  decides from where the hook runs, never from the payload. Inside a
  Nika project — a `nika.yaml` or a `.nika/` store in the host's project
  directory (`CLAUDE_PROJECT_DIR`, `CURSOR_PROJECT_DIR`), in the hook's
  working directory, or above either; `~/.nika` does not count — it
  refuses every shell command with `guard_unavailable` until the binary
  is back. Elsewhere it lets commands through and warns once, as
  `guard_off` on stderr with exit 1: Claude Code shows it as a hook
  error notice, Cursor logs it, Codex records that the hook failed. The
  warning comes back after the binary has been found and lost again (a
  marker under `${XDG_STATE_HOME:-~/.local/state}/nika/`, or under the
  temporary folder when that one cannot hold it). Meanwhile no
  run is judged: a `nika run` started by an absolute path outside a
  project is not checked by this hook. A hook set to block on failure
  (Claude Code `onFailure: "block"`, Cursor `failClosed`) turns the
  warning into a refusal; the kit's wiring, and the one `nika init`
  writes, sets neither.
- **A healthy guard speaks only about `nika run`.** Every other parsed shell command
  the agent proposes passes through untouched — the hook returns no
  decision at all, so your host's own permission flow decides exactly
  as it would without the kit installed. A judge that breaks or cannot
  judge never returns that no-opinion verdict; a missing one returns it
  only outside a Nika project, after its one warning (the rules above).
  An affirmative « proceed » is only ever earned by a run the ladder
  just saw clean.
- **Windows**: the manifests start every hook with `/bin/bash`, which
  Windows does not have (there Cursor's desktop app runs hook commands
  through PowerShell, <https://cursor.com/docs/hooks>, read 2026-11-26),
  so no hook can start, and on all three hosts a hook that cannot start
  lets the command through: the comfort hooks and the run guard are off,
  and commands fall back to the host's own permission flow. `nika doctor`
  names the missing rails; `nika run` itself still refuses a workflow
  whose `nika check` is not clean, and `permits:` and cost caps still
  hold.
- The engine stays the authority: hooks are a seatbelt, never the
  airbag. Everything the oracle answers is read-only by design: the
  MCP oracle audits and teaches; execution uses the host's visible shell
  tools under the user's authorization and the engine's admission boundaries.

## Links

Docs: <https://docs.nika.sh> · Spec: <https://github.com/nika-open/nika-spec>
· Site: <https://nika.sh> · Engine (AGPL-3.0-or-later):
<https://github.com/nika-open/nika>

Created and maintained by Thibaut Mélen ([@ThibautMelen](https://github.com/ThibautMelen)) ·
SuperNovae Studio.
