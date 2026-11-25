---
type: llm
---

PASS if the workflow gives the labelling step a cheaper model route than the summary step (a `model:` inside the `infer:` of one of the two tasks, over the workflow's default), and the reply says in a line or two which step got which route and that the choice of a paid route stays the user's to change.
FAIL if both steps use the same model, if the cheaper route is on the summary, or if the reply never says which step runs on which route.
