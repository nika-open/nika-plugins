# Engine behaviors to design around

Read this reference for the matching task; return to [the skill](../SKILL.md) for scope and completion.

Each was measured on 0.125.0 with `nika check`, and with runs where a
run is named. Design around them; none is a defect of your file.

## A secret's taint reaches every value of the call

A call that uses a secret (`nika:notify` to a webhook held in a secret, a
`nika:fetch` with the token in a header) returns values that all carry the
secret's taint: the output, the response and the status alike. Binding any
of them into a write's arguments is refused `NIKA-SEC-006`. To record that
the call happened, gate the downstream task with `when:` alone and keep the
tainted value out of its arguments (`after: { alert: success }` works too):

```yaml
nika: alert-then-record
secrets:
  team_hook:
    source: env
    key: TEAM_WEBHOOK_URL
    egress:
      - to: "nika:notify"
        host_from_self: true
permits:
  tools: ["nika:notify", "nika:write"]
  net:
    http: ["hooks.slack.com"]
  fs:
    write: ["./out/sent.txt"]
tasks:
  alert:
    invoke:
      tool: "nika:notify"
      args: { channel: webhook, target: "${{ secrets.team_hook }}", message: "Nightly report is ready" }
  record:
    with:
      sent: ${{ tasks.alert.status }}
    when: ${{ with.sent == 'success' }}
    invoke:
      tool: "nika:write"
      args: { path: "./out/sent.txt", content: "sent", create_dirs: true, overwrite: true }
```

Keep the secret's `egress:` narrow: one `to:` and, for `nika:fetch`, its host
(`egress: [{ to: "nika:fetch", host: "api.example.com" }]`). The fix line
that adds `nika:write` to `to:` would also clear the finding, and would let
the secret's flow reach the file: never widen it just to read a status.

## Expressions

`${{ }}` and `when:` speak `cel-subset/0.1` (spec 03 §Formal grammar).
Measured:

- Accepted: `==`, `!=`, `<`, `<=`, `>`, `>=`, `in` against a list, `&&`,
  `||`, `!`, parentheses, field access, indexing (`with.items[0]`),
  `size(x)` and `x.size()`, `has(x.field)`, `x.contains(s)`,
  `x.startsWith(s)`, `x.endsWith(s)`, a comparison with `null`, and the
  conditional `c ? a : b`.
- Roots in `when:`: `with.`, `inputs.`, `const.`. A `tasks.` reference there
  is `NIKA-VAR-021`: bind it with `with:` first.
- Refused at check, `NIKA-VAR-005`: arithmetic (`+`, `-`, `*`, string
  concatenation included), the macros `map()` and `all()`, `matches()` and
  every other method (`lowerAscii()`), a chained relation (`1 < with.n < 5`),
  a bare reference (`when: ${{ with.flag }}`: write `with.flag == true`).
- Refused at run, `NIKA-VAR-006`: `in` against a map (`'k' in with.obj`).
  Test a key with `has(with.obj.k)`.
- Quote a value that holds a conditional: unquoted, YAML reads `a ? b : c` as
  a mapping (`NIKA-PARSE-001`).

Arithmetic belongs to `nika:jq`: compute the number or the boolean there,
bind it with `with:`, compare it in `when:`. A time span is a duration
string (`timeout: "90s"`, `nika:date` `duration: "P1D"`), never a product.

## Field and tool limits

| Limit, as measured | Workaround |
|---|---|
| `nika:image_fx` `ops:` from `${{ }}` is refused `NIKA-BUILTIN-001` | write the op list literally in the task |
| YAML anchors and aliases (`&say`, `*say`) are refused `NIKA-PARSE-001` | repeat the block |
| `max_tokens:` from `${{ }}` is refused `NIKA-PARSE-019` | a literal number in the task |
| `infer.schema:` from `${{ const.x }}` is refused `NIKA-PARSE-019` | write the schema out in the task, and again in `nika:validate` when both use it |
| jq has no `\p{…}` class: `test("\\p{L}")` is refused `NIKA-VAR-005` | a code-point range: `test("[\\x{0590}-\\x{05FF}]")` works |
| jq `label` is a keyword: `def label: …` is refused `NIKA-VAR-005` | name the function otherwise; `.label` and `{label: .}` work |
| `nika:date` refuses a bare date (`base: "2026-11-24"`) at run, `NIKA-BUILTIN-DATE-001` | a full RFC 3339 timestamp (`2026-11-24T00:00:00Z`), or `op: parse` with `format: "%Y-%m-%d"` first |
| `nika:chart` `semantics:` knows one money grain, `usd`; `eur` is refused | convert with `nika:jq` and label the axis, or use `count` |
| a `nika:decide` receipt is one object | route a lane on `with.receipt.outcome` in `when:`; derive anything finer (a dimension, a list) with `nika:jq` first |

## Downloading images and other binary files

`nika:fetch` refuses a body that is not text: fetching an image in
`mode: raw` fails `NIKA-BUILTIN-FETCH-001` (« response body is not valid
UTF-8 »), measured. Binary is file-mediated: an `exec:` of `curl --fail
--location --output <path> <url>`, with `permits.exec: ["curl"]`, the host
in `net.http` and the path in `fs.write`, then the path feeds `nika:image_fx`,
`nika:image_compose` or `infer.vision`. Plain check admits it;
`--native-strict` flags it `native-first/001`, pointing at `nika:fetch`,
which cannot do it. That flag cannot clear on 0.125.0: say so in the
hand-over instead of looping. An MCP tool that returns image content also
works: its bytes flow into `nika:write` `content:`.

## A skipped write leaves the last run's file

`when:` skips a task; it does not undo what an earlier run wrote. An alert
written on Monday is still there on a quiet Tuesday, and a reader takes it
for today's. Two ways out:

- Always write the report, with no `when:`, and let its content say that
  nothing is new.
- Remove the stale artifact on the quiet branch with `nika:remove_file`,
  under the same `fs.write` bound. Order the removal after the skipped write
  (`after: { alert_file: skipped }`): two unordered tasks on one path are
  refused `NIKA-SEC-012`. Removing a missing file fails
  `NIKA-BUILTIN-REMOVE_FILE-002`; recover it for the quiet run that finds
  nothing to remove.

```yaml
nika: alert-file
inputs:
  alerts:
    type: { array: string }
    required: false
    default: []
permits:
  tools: ["nika:jq", "nika:write", "nika:remove_file"]
  fs:
    write: ["./out/alert.md"]
tasks:
  count:
    with:
      alerts: ${{ inputs.alerts }}
    invoke:
      tool: "nika:jq"
      args: { expression: "length", input: "${{ with.alerts }}" }
  alert_file:
    with:
      n: ${{ tasks.count.output }}
      alerts: ${{ inputs.alerts }}
    when: ${{ with.n > 0 }}
    invoke:
      tool: "nika:write"
      args: { path: "./out/alert.md", content: "alerts: ${{ with.alerts }}", create_dirs: true, overwrite: true }
  clear_alert:
    after: { alert_file: skipped }
    on_error:
      recover: "absent"
      on_codes: ["NIKA-BUILTIN-REMOVE_FILE-002"]
    invoke:
      tool: "nika:remove_file"
      args: { path: "./out/alert.md" }
```

Measured: a run with an alert writes the file, the next quiet run removes it,
and a third quiet run recovers the missing file. Without `clear_alert`, the
quiet run leaves Monday's alert in place.

## Rehearsing with mock

`--model mock/echo` answers without a model, measured: plain text comes back
as `mock(echo) · <the prompt>`; a typed answer takes the first `enum` value,
`0` for an integer, `false` for a boolean and `"mock"` for a string. So:

- List the safe value first in every enum (`enum: ["hold", "send"]`), so a
  rehearsal takes the conservative branch.
- Prove each law on hand-known fixtures with `nika:assert`
  (`13-extract-then-law`): the law's branches then run with no model.
- For a branch that needs a particular answer, rehearse a scratch copy where
  the `infer:` task becomes a `nika:jq` returning a fixture of the same shape;
  check it, run it, delete it. `nika test --case <name> --var <key>=<value>`
  pins each input-driven case in its own golden.
- Mock removes inference only: the file's tools, writes and fetches are real.

## Resume

`nika run <file> --resume <trace>` skips the tasks the trace settled. A trace
with no resume keys (measured on a run whose only task failed) says it
« carries no resume keys » and is « running everything live »: every task
runs again, effects included. Read that line before resuming a run that wrote or
sent something.

## Two hints that cannot both clear

When a model answer feeds a `nika:jq` or `nika:decide` law and the job
writes, check raises `unproven-law` until the law is proved on a hand-known
fixture with a `nika:assert` (`13-extract-then-law`). That assert then raises
`assert-quarantine`, which fires for any `nika:assert` in a workflow that
writes, wherever it sits. On 0.125.0 the two cannot both clear. It is a
known engine limit, not a defect in the file: clear `unproven-law`, which
blocks `paid_ready`, and read `assert-quarantine` as advice, since it blocks
neither `clean` nor `paid_ready` (a red assert moves the run's writes to
`.nika/quarantine/<trace>/`). Name it once in the hand-over and stop there.
