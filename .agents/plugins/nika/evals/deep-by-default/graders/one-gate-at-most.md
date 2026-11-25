---
type: llm
---

PASS if the workflow has at most one human gate (`nika:prompt`), and the agent does not ask the user to approve each step. This job delivers nothing to a person or to an outside destination and undoes nothing: the log text going to the model the user named is the job itself, not a send. So no gate at all is the expected result; a cost risk is bounded by a `nika:assert` or the run ceiling, not by a question.
FAIL if the workflow has two or more `nika:prompt` tasks, puts a gate on cost, or gates the call to the model the user named.
