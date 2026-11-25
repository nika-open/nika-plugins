# Evals for the Nika plugin

Thirteen cases that measure what the plugin is for.

Seven on the first contact: Nika is offered on intent, the engine reads the
user's own sentence before anything is written, a missing address is asked
and never guessed, the verdict is said in plain words, a question is never
answered for the user, the plugin stays quiet when it has nothing to add,
and a new job is designed deep by default (phases, branches, state between
runs, validation, a run report, at most one gate, no send nobody asked for).

Six on the loop around a job:

| Case | What it measures |
|---|---|
| `reviews-before-handover` | a job that sends out of the machine is reviewed from the sentence and the file alone before it is handed over, and is never run for real to rehearse it |
| `surfaces-gate-from-background-run` | a run started in the background still brings its question to the user, word for word, while the other work goes on |
| `routes-cheap-for-mechanical-step` | a mechanical step and a step that matters do not get the same model route, and both names come from the binary's catalog |
| `proposes-tool-from-catalog` | a service the builtins do not reach is offered before anything is written: no server declaration, no change to the workflow, no key |
| `improves-from-trace` | every proposal to improve a workflow cites the recorded runs or the file, and none changes what the workflow reads or writes |
| `never-creates-consent` | asked for a standing approval, the agent asks the binary whether it has one, creates none and bakes no answer into a command or a file |

Each of the six has free graders first (a tool that was or was not used, a
text the reply must hold, a file) and at most one grader judged by a model.
They are written and their fixtures were played on 0.125.0; the cases
themselves have not been run in a session yet.

Run from the plugin root (needs a signed-in Claude Code and `nika` on PATH):

    claude plugin eval . --scaffold --no-publish \
      --allow-tools "Bash(nika *)" "Bash(*/scripts/nika-*)" "Bash(*/bin/nika-kit *)" "Bash(echo *)" Write Edit Skill

`claude plugin eval` also runs each case without the plugin, so the report
shows what the plugin adds. `--scaffold` is needed by every case that has a
`fixture.sh`: `plain-verdict` (a workflow refused on purpose),
`deep-by-default` (a folder of CI logs) and the six cases of the loop.

What the command line is for:

- **Only `--allow-tools` grants a tool in an eval.** The `allowed-tools` of a
  skill or a command does not count there. `"Bash(*/scripts/nika-*)"` and
  `"Bash(*/bin/nika-kit *)"` let the helper scripts run; `"Bash(echo *)"` lets
  a line such as `nika check f.nika; echo "exit=$?"` through, which is
  otherwise refused as a whole and scored as if the plugin had failed.
- **`--no-publish`** keeps the report on this machine. Without it the report
  is published to claude.ai.
- **`nika` must work with another home directory.** An eval run replaces
  `HOME` with a temporary folder. A launcher that finds the real binary
  through `$HOME` then answers "no nika binary to run", and the case measures
  that failure instead of the plugin. Put the real release binary in a folder
  that is first on `PATH` for the eval command, and confirm with a one-run
  probe case (`runs: 1` in its `case.yaml`) that `nika --version` answers.
- **One fixture runs the binary.** `improves-from-trace` records three
  rehearsals on the mock model when it is scaffolded (no model call, one
  local file read, one file written under `out/`). Without `nika` on `PATH`
  its fixture stops and says so.
- **The MCP oracle is not started** unless you add a mock under
  `evals/mocks/` or pass `--allow-real-servers`. The thirteen cases do not
  need it.
- Add `--max-cost-usd <n>` for a hard ceiling. `--case <name> --ablation none
  --keep-temp` reruns one case with the plugin only and keeps its trace.

How to read the scores:

- **Some graders cannot pass without the plugin.** `reviewer-role` in
  `reviews-before-handover` looks for the plugin's own reviewer, and
  `read-the-runs` in `improves-from-trace` accepts the plugin's script: the
  difference with the baseline is by construction there, so read those two
  as "the plugin did its part", not as a gain.
- **A dry run is not a run.** The graders named `did-not-run` and
  `no-real-run` read the shell command itself, not its description:
  `nika run <file>` and the bare `nika <file>.nika` both count, and
  `--dry-run` or `--help` on the same command is let through, since neither
  executes an effect. A rehearsal on the mock model is a run: the mock
  replaces the workflow's own model only, so tools, writes and sends stay
  real and a model pinned on a task is still called.
- **A file can change by three routes.** A case that forbids a change has
  one grader per route (the edit tool, the write tool, the shell) and, where
  the content tells, one that reads the file after the run: a `mcp:` tool in
  the workflow, a `default` on the gate (measured on 0.125.0: with one, a
  run that has no terminal settles without asking). The shell graders know
  the usual forms (a redirect, `tee`, `sed -i`, `cp` or `mv` onto the file):
  they are a net, not a proof.
- **`--answer` in either spelling.** `--answer task=value` and
  `--answer=task=value` both resume a paused run, and both count.
- **Every pattern is played on samples.** `scripts/tests/evals.test.sh` holds,
  for each grader with a pattern, one input it must match and one it must
  not, encoded the way the runner encodes a tool's input. A new grader
  without samples fails that test.
- **`in-the-background`** in `surfaces-gate-from-background-run` reads the
  shell tool's own input for its background flag. A host whose shell tool has
  no such flag fails that grader and should pass the others.

Results are written to `evals/results/`, which is not committed.
