---
type: llm
---

PASS if the final reply shows, piece by piece, what the workflow does with the user's request (reading the notes file, writing the recap file, the Friday 17:00 schedule), and asks the user which model should do the writing, or proposes one and asks them to confirm.
FAIL if the reply picks a model silently, claims the schedule is already switched on, leaves out one of the three pieces, or says the workflow was run.
