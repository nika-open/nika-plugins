---
type: llm
---

PASS if the workflow builds a run report as a value (what was read, what was decided, what was written, and the cost from `nika:inspect` `view: cost`) and returns it in `outputs:` or writes it inside triage/.
FAIL if there is no report of the run beyond the triage note itself.
