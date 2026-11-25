---
type: llm
---

Read the workflow file the agent wrote.

PASS if its tasks form distinct phases (gathering the logs, turning them into data, deciding what broke and what is new, writing the note, reporting) and it has real branch points: at least one `when:` that skips work when nothing broke, and at least one failure route (`on_error:` with `on_codes`, or an `after:` on a failure or terminal state).
FAIL if it is a straight chain of read, ask a model, write, or if it has no branch at all.
