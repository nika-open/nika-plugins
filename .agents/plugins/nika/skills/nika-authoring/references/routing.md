# Routing: which model does which step

A job rarely needs one model for every step. A step that copies three
fields out of a log and a step that weighs two designs do different work,
and paying the second one's price for the first is the most common waste a
workflow carries. This guide is a method. It names no model and no price on
purpose: both change between releases, and the binary knows today's.

## The person's model comes first

The workflow's `model:` is the model the person chose, or the one their
machine can reach. Keep it as the default. A `model:` inside one task's
`infer:` (a `model:` set directly on a task is refused) is the exception,
and it is theirs to accept when it changes who is paid or who
sees the data: another provider, a paid route where the default was local,
a cloud route where the default kept data on the machine. Offer it in one
line with what it changes; add it on a yes. Never pin a stronger model than
the one they chose: when a step needs more, say so and let them raise the
default.

## Six roles

Name the role of each model step before choosing its route.

| Role | The step | It needs | How you know it worked |
|---|---|---|---|
| extract | copies facts out of text into fields | a schema, a small output | every field validates; a missing fact is `null`, not invented |
| classify | puts an item in one of a few named classes | an enum, a few tokens | the answer is one of the classes, on every item |
| judge | weighs evidence and decides | reasoning, the evidence in the prompt | the verdict cites what it rests on; a second run agrees |
| write | drafts prose a person will read | room in the output | a person, or a check you can state (length, sections, language) |
| plan | breaks a goal into steps another task executes | reasoning, structured output | the plan parses and each step names something that exists |
| see | reads an image or a page as an image | vision | the fields validate against what the image shows |

Extract and classify are mechanical: small answers, a schema that proves
them, many items. They are the first candidates for a cheaper route. Judge
and plan are where a weaker model costs more than it saves, in repairs and
in wrong verdicts nobody catches.

## Reading the catalog

`nika catalog --json` is the list this binary can route to. Per provider:
`resolves` (the binary can route there), `local` (it runs on this machine),
`default_model`, `cheap_model` (the provider's own cheaper tier) and
`tags`. Per model: `paste_id` (the id to write, copied as printed),
`context_window_tokens`, `max_output_tokens`, and `capabilities` with
`reasoning`, `vision` and `json_mode`.

1. Keep the providers the person can use: the one their default model
   belongs to, and any other they named or hold a key for. The catalog
   lists what the binary knows, not what this person pays for.
2. Keep the models whose `capabilities` cover the role: `vision` for see,
   `reasoning` for judge and plan, a `json_mode` that takes a schema for
   extract, classify and plan.
3. Check the sizes: the prompt and its inputs fit `context_window_tokens`,
   and the task's `max_tokens` fits `max_output_tokens`.
4. For a mechanical role, start from the provider's `cheap_model`.
5. Write the `paste_id` exactly as printed. A model name from memory is how
   a file ends up naming a model the binary does not know.

## Reading the price off the check

The catalog does not print prices; the check computes them. Put the
candidate in the task's `infer:` and read `nika check <file> --json`:

- `cost.tasks[]` gives each model step its `model`, `max_tokens` and `usd`,
  the ceiling of what its answers can cost per run. `unbounded_reason`
  says why there is no ceiling (a missing `max_tokens`, a fan-out of
  unknown size, a model the table does not price).
- `data_journey.model_endpoints[]` gives each step its `provider`, `locus`
  (on this machine or not), `priced`, and what the provider keeps
  (`retention`, `trains`).

Compare two routes by changing one task's `infer.model` and reading those two
places again. `usd` covers the output side only: input billing is not in
it, so a step with a long prompt and a short answer costs more than the
line says. An unpriced step (`priced: false`) is a local or seat model: no
price in the table, never free.

## Routing is also about where the data goes

`locus` and `retention` are part of the choice. Moving a step that reads
private files from a local model to a cloud one changes who sees those
files, even when it is cheaper and better. That is an effect, and it is
offered like any other.

## Prove it before keeping it

A cheaper route is a proposal until it has passed, on real inputs, the same
validation the step passed before: the same schema, the same `nika:assert`,
the same enum. A mock rehearsal proves the shape of the job, not the
answers of a model. Running on real data and on a paid route is the
person's yes. `/nika:improve` finds the candidates in the recorded runs of
a workflow, with their evidence.

A seat route (`run.access`) is a different axis: it chooses the path to a
model, not the model. See [Seats and images](seats-and-images.md).
