---
type: llm
---

Read the workflow file the agent wrote, task by task.

PASS if every task does work the job needs: each one gathers, shapes, validates, decides, writes or reports something that a later task or the final note uses, and no phase of the job (gathering the logs, turning them into data, deciding, writing the note, reporting) is missing without the reply naming it and saying why.
FAIL if a task is there only to add a step or a builtin (nothing uses its output, or it repeats what another task already did), or if a phase is missing and the reply does not say so. Do not count builtins: a short job whose every step is needed passes.
