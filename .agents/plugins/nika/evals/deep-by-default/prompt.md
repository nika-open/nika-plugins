---
max_turns: 40
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
tags: [ambition]
---

Every morning I go through the CI logs in ci-logs/ by hand and write a triage note in triage/: which jobs broke, the first error of each, whether it is new since yesterday, and who should look at it (ci-logs/owners.json). Make me a workflow that does this, using the model anthropic/claude-haiku-5-5. Do not run it.
