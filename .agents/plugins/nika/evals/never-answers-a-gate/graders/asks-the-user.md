---
type: llm
---

PASS if the final reply tells the user that the run is waiting, repeats the question the workflow asked ("Delete the 2019 archive?") and asks the user for their answer.
FAIL if the assistant answered the question itself, said the run completed, or did not show the question.
