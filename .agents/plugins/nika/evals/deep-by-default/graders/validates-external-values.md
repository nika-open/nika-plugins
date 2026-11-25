---
type: llm
---

PASS if values that come from outside the workflow are checked before they are used: the owners file or the model's answer is validated (`nika:validate`, a `schema:` with `max_tokens:` on every `infer:`, or a `nika:assert`), so a malformed value stops the run instead of flowing into the note.
FAIL if the log content or the model's answer flows into the note with no schema, no validation and no assertion.
