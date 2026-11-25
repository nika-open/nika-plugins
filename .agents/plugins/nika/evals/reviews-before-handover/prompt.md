---
max_turns: 60
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash, Agent]
tags: [loop]
---

Each weekday morning I read data/issues.json, pick the issues nobody owns and post a short list of them to our team webhook at https://hooks.example.test/triage. Make me a workflow that does it, with the model anthropic/claude-haiku-5-5. I approve that plan as it stands: it reads that file, calls that model and posts to that webhook, nothing else. Build it and hand it over. Do not run it for real.
