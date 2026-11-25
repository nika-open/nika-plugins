#!/usr/bin/env bash
# Scaffold for the improves-from-trace case: a triage workflow and the record
# of three rehearsals of it. Two things can be proven from the file and the
# records: the fan-out sends the same long instruction with every ticket, and
# no recorded run ever took the escalation branch. The three runs are on the
# mock model, so they say nothing about cost. The case measures that every
# proposal cites that evidence and that none changes what the workflow reads
# or writes.
#
# The rehearsals call no model, read one local file and write under out/.
set -eu
command -v nika >/dev/null 2>&1 || {
  echo "fixture: nika is not on PATH, the rehearsals cannot be recorded" >&2
  exit 1
}
mkdir -p in
cat >in/tickets.json <<'JSON'
[
  "I was charged twice for the March invoice.",
  "The export button does nothing on Safari.",
  "How do I add a second user to my account?"
]
JSON
cat >triage.nika <<'NIKA'
nika: ticket-triage
model: mock/echo
permits:
  tools: ["nika:read", "nika:jq", "nika:write"]
  fs:
    read: ["./in/tickets.json"]
    write: ["./out/triage.json", "./out/escalation.md"]
tasks:
  source:
    invoke:
      tool: "nika:read"
      args: { path: "./in/tickets.json" }
  tickets:
    with: { raw: "${{ tasks.source.output }}" }
    invoke:
      tool: "nika:jq"
      args: { input: "${{ with.raw }}", expression: "fromjson" }
  count:
    with: { items: "${{ tasks.tickets.output }}" }
    invoke:
      tool: "nika:jq"
      args: { input: "${{ with.items }}", expression: "length" }
  classify:
    with: { items: "${{ tasks.tickets.output }}" }
    for_each:
      items: ${{ with.items }}
      max_parallel: 2
      fail_fast: false
    infer:
      prompt: |
        You are the first reader of the support inbox of a small software
        company. Read the ticket below and answer with one word, the lane it
        belongs to. The lanes are: billing, for anything about an invoice, a
        charge, a refund, a card or a plan; bug, for anything that does not
        work as the product says it should; question, for anything the person
        could have found in the help pages. When a ticket fits two lanes,
        prefer billing over bug and bug over question. Do not explain your
        choice and do not repeat the ticket.
        Ticket: ${{ item }}
      max_tokens: 2000
  escalate:
    with: { n: "${{ tasks.count.output }}", lanes: "${{ tasks.classify.output }}" }
    when: ${{ with.n > 100 }}
    infer:
      prompt: "More than a hundred tickets arrived. Write a short note for the team lead from these lanes: ${{ with.lanes }}"
      max_tokens: 400
  save:
    with: { lanes: "${{ tasks.classify.output }}" }
    invoke:
      tool: "nika:write"
      args: { path: "./out/triage.json", content: { lanes: "${{ with.lanes }}" }, create_dirs: true, overwrite: true }
NIKA
for _ in 1 2 3; do
  nika run triage.nika --model mock/echo --max-cost-usd 0.10 --plain --no-progress >/dev/null 2>&1 || true
  sleep 1
done
