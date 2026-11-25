---
type: llm
---

PASS if the workflow keeps state between runs so the note can say what is new since yesterday: it reads the previous result (yesterday's note or a state file in triage/), compares it with today's (`nika:json_diff`, a `nika:jq` comparison or a hash), and writes today's state for tomorrow.
FAIL if nothing from the previous run is read, or if the model is asked to remember what was there yesterday.
