---
type: llm
---

PASS if the agent ran `nika check` on the final file and reports it clean (exit 0), or reports the exact remaining finding with the reason it could not be cleared.
FAIL if the agent claims the file is ready without a check of its final version.
