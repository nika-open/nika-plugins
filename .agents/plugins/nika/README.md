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
authoring skill, the three hooks, the Cursor rules and subagents, and the
oracle wiring.

## What one install gives your agent

| Component | What it does |
|---|---|
| `nika-authoring` skill | a concise authoring entry with task-specific language and validation references |
| `nika-debugging` skill | run forensics: trace ls → show → outputs → verify · resume lines · surgical reruns |
| `nika-operating` skill | day-2 hardening: spend caps · permits · secrets · model swaps · CI goldens · OTLP export |
| `nika-migration` skill | convert scripts, CI jobs and prompt chains to workflows — mapping table + parity protocol |
| `nika-author` subagent | writes or repairs the requested artifact, checks it and reports blockers; launching belongs to the conversation |
| `nika-debugger` subagent | root-causes a failed or paused run from its hash-chained trace, hands back the exact resume line |
| `nika-migrator` subagent | ports existing automation: inventory → native-first mapping → check loop → golden pin |
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
| `/nika:run` · `/nika:pending` · `/nika:make` | check, then run with one confirmation · list the runs waiting for an answer · turn the user's own sentence into a workflow: the engine reads the sentence first (`nika compile`, no model call), the agent asks only the engine's questions and writes by hand only what the engine could not read |
| language server (Claude Code) | `nika lsp` wired through `.lsp.json`: the findings of `nika check` reach the agent after each edit, with no process started per edit. Terminal sessions only; the check-on-edit hook covers the rest |
| session-status hook (Claude Code) | says at session start that the binary is missing (the guard then refuses every shell command inside a Nika project and warns once elsewhere), or that a run in the workspace is waiting for an answer |
| intent hook (Claude Code) | a prompt that sounds like a schedule, a batch or "do it again" gets ONE hint per session; when the engine can read the sentence, the hint already carries its reading (pieces, schedule, questions). Silent otherwise, no model call, and nothing is written in the project |
| stop gate (Claude Code) | a `*.nika` changed during the session that fails `nika check` sends the agent back once, with the reason in plain words; it also catches files written through the shell, which the edit hook and the language server never see |
| waiting-runs monitor (Claude Code) | prints one line when a run starts waiting for an answer, while the `nika-running` skill is in use; interactive sessions only |
| `port-to-nika` workflow (Claude Code) | ports many files at once (n8n exports, scripts), one agent per file, each result checked, with a report of what could not be ported. Written and syntax-checked, not yet run in a session |
| `evals/` | six cases for `claude plugin eval` (see `evals/README.md`): offered on intent · the engine reads the sentence first · a missing address is asked, never guessed · plain verdict · never answers a question for the user · stays quiet when it has nothing to add |
| `max_cost_usd` setting (Claude Code) | the spending cap `/nika:run` puts on every run unless the user names another one; asked once when the plugin is enabled |

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
  bounded reader and never guesses scope or host dialect.
  The other deny is a run on a file with
  live check findings — the denial carries the findings, so the agent
  repairs and re-checks by itself.
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
  marker under `${XDG_STATE_HOME:-~/.local/state}/nika/`). Meanwhile no
  run is judged: a `nika run` started by an absolute path outside a
  project is not checked by this hook. A hook set to block on failure
  (Claude Code `onFailure: "block"`, Cursor `failClosed`) turns the
  warning into a refusal.
- **A healthy guard speaks only about `nika run`.** Every other parsed shell command
  the agent proposes passes through untouched — the hook returns no
  decision at all, so your host's own permission flow decides exactly
  as it would without the kit installed. A judge that breaks or cannot
  judge never returns that no-opinion verdict; a missing one returns it
  only outside a Nika project, after its one warning (the rules above).
  An affirmative « proceed » is only ever earned by a run the ladder
  just saw clean.
- **Windows**: the hooks are bash scripts; without a bash on PATH the
  hook processes cannot run — comfort AND guard rails are effectively
  absent (runs fall back to the host's own permission flow, unguarded).
  `nika doctor` names the missing rails; the engine's own boundaries
  (`nika check` · `permits:` · cost caps) still hold whenever you run
  the binary yourself.
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
