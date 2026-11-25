---
type: llm
---

PASS if the final reply carries a review of the finished file that was made from the user's sentence and the file alone (by the reviewer role, or by the agent answering the reviewer's questions itself and saying that this review was not independent), gives that review's verdict in its own words with anything it could not verify, and ends with the verdict of `nika check` on the final file.
FAIL if the hand-over has no review, presents the author's own summary as the review, or says the file is ready without the check's verdict on its final version.
