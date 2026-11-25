# Seats and images

Read this reference for the matching task; return to [the skill](../SKILL.md) for scope and completion.

## Two ways to reach a model

By default the engine runs its own loop over an API or a local model:
`model: <provider>/<name>` and a key or a local server. `run.access` declares
another route for the whole run (spec 01 §run):

| Key | Values | Meaning |
|---|---|---|
| `run.access.via` | a kebab-case id | an agent application (`codex`, `claude-code`; `nika run --help` lists the seats under `--access`) or an API provider id (`openai`) |
| `run.access.protocol` | `acp` or `api` | `acp`: an Agent Client Protocol session with the application · `api`: the route's inference API |
| `run.access.fallback` | `none` | the only value, and the meaning of an omitted `fallback`: no other route, protocol or model replaces the declared one |

- Every value is a literal. One route serves every `infer:` and `agent:` task
  of the run; there is no task-level `access:`. A `--access` or `--model` on the
  command line that contradicts the file is refused, never preferred.
- Use `agent:` tasks on a seat. An ACP seat is not thereby fit for `infer:`
  (spec 02 §Subscription harness access).
- A seat is unpriced: its budget is the subscription's quota, never 0 USD.
  Check reports the task as unpriced; keep `max_turns` and `max_tokens_total`.
- A seat widens effects. On a seat the application runs its own tools, and
  `permits:` does not bound what its mode lets it do without asking: check
  prints a `[harness]` hint naming them, and `nika explain harness` teaches
  the whole contract. Adding a seat route is therefore an effect-widening
  change: propose it in one line, never add it in silence.

## Seat images: `agent.images`

An `agent:` task on a seat can keep the images the application draws during
its turn (spec 02 §Harness images). This file is the specification's banner
example inside a complete envelope:

```yaml
nika: release-banner
inputs:
  product: { type: string, required: true }
run:
  access:
    via: codex
    protocol: acp
permits:
  tools: ["nika:image_fx"]
  fs:
    read: ["./out/release/**"]
    write: ["./out/release/**"]
tasks:
  banner:
    agent:
      prompt: "Draw a 16:9 release banner for ${{ inputs.product }}, no text"
      max_turns: 4
      max_tokens_total: 20000
      images:
        save: "./out/release/banner.png"
  halftone:
    with:
      banner: ${{ tasks.banner.output.images[0].path }}
    invoke:
      tool: "nika:image_fx"
      args: { input: "${{ with.banner }}", out: "./out/release/banner-halftone.png", ops: [{ halftone: {} }] }
outputs:
  banner: ${{ tasks.banner.output.images }}
  note: ${{ tasks.banner.output.message }}
```

- **The value.** With `images:` set, `.output` is `{ message, images }`.
  `message` is what `.output` would be without it (the final message, or the
  object matching `schema:`). Each image is
  `{ index, path, sha256, size_bytes, mime_type, width, height }`, in delivery
  order; `path` is `null` without `save:`.
- **This session's bytes only.** An image counts when its bytes arrived on
  this task's own session. A path the application reports (its shared
  generated-images folder) is never opened, listed or saved.
- **The `-n` naming and the four-image limit.** The first image lands at the
  `save:` path, image *n* (2 to 4) at the path with `-n` before the extension
  (`banner.png`, `banner-2.png` … `banner-4.png`). A fifth image fails the task
  before any file is written.
- **The permits judgment.** Every one of the four paths is judged against
  `permits.fs.write` before any byte is written. An exact-file grant holds the
  first image only: check refuses it `NIKA-SEC-004`, naming `banner-2.png`.
  Grant the folder, or the four names `nika check --infer-permits` derives.
  With no `permits:` block a save of any form is `NIKA-AUTH-006`; under
  `permits: {}` it is `NIKA-SEC-004` (conformance `authority/050`, `051`,
  `055`, `056`).
- **Nothing received.** A task whose session delivered no image bytes fails
  `NIKA-AGENT-007`: the declared file is never left missing behind a success.
- **The next step reads the file.** A builtin that opens the saved image
  (`nika:image_fx`, `nika:image_compose`, `infer.vision`) needs its folder in
  `fs.read` too. Measured on 0.125.0: without that grant check stays clean,
  its drift hint even proposes to drop the read entry, and the run fails the
  fx step `NIKA-SEC-004`.

## `nika:image_generate` or seat images

| | `nika:image_generate` | `agent.images` on a seat |
|---|---|---|
| Who draws | a provider (`openai`, `gemini`, `xai`), a `local` server, or `mock` | the agent application's own image tool, during its turn |
| Control | `size`, `aspect_ratio`, `n` up to 10, `quality`, `format`, `mode: edit` with source images and a mask | the prompt; at most four saved images |
| Output | `.output.images[n].path`, a provenance manifest | `.output.images[n].path` with `save:` |
| Rehearsal | `provider: mock` writes a real PNG with no network | none under mock (below) |
| Reach for it when | the job needs exact sizes, variants, an edit of a given picture, or a run without a seat | the person already works in that application, or the image belongs to a larger agent turn (draw after reading the repository) |

Both expose `images[n].path`, so the steps after them do not change when the
source does. Choosing a seat is still the effect-widening change above.

## What runs under `--model mock/echo`, and what needs the seat

Measured on 0.125.0 with `nika check` only (no run, no seat session; check
probes the seat's login command, it does not open a session):

- A file declaring `run.access: { via: codex, protocol: acp }` with
  `agent.images.save` passes check: exit 0, `clean`, `native_strict_clean`,
  `run ready ok` where the seat answered its login. The same holds for
  `via: claude-code`.
- `nika check --model mock/echo` on that file: exit 0 and `clean: true`, but
  `access ready` and `run_ready` are false: « model `mock/echo` is the
  isolated rehearsal backend and cannot run through a harness seat … (refusal,
  never a live substitute) ». Check therefore predicts that a mock run of a
  seat workflow is refused before inference.
- `nika check --access mock` on it: refused, « contradicts the workflow's
  `run.access.via: codex` … an explicit selection is never silently
  replaced ».
- `agent.images` with no seat (`model: mock/echo`, no `run.access`): exit 0,
  `clean: true`, `run_ready: false`: « no seat serves it here (the run refuses
  it) ».

Read `run_ready` in `nika check --json` (or the `layers` line), not only the
exit code: these refusals keep exit 0. A seat workflow has no mock rehearsal.
Rehearse around it: put the steps after the image in a workflow that takes the
image path as an input, and feed it an image from `nika:image_generate` with
`provider: mock` or a committed PNG. Everything else under `--model mock/echo`
stays real: tools, writes and fetches.
