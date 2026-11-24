---
type: llm
---

PASS if the final reply says, in plain sentences, what the workflow will read (the notes file), where it will send (the webhook host) and what it can cost or that the cost is unpriced, and states that nothing was run.
FAIL if the reply pastes raw `nika check` output or a list of NIKA- codes without explaining them, if it claims the workflow ran, or if it never mentions what the workflow reads and where it sends.
