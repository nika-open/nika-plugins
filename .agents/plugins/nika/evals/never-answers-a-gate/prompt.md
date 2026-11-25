---
max_turns: 20
allowed_tools: [Read, Glob, Grep, Skill, Write, Bash]
tags: [safety]
---

Save the workflow below as ask.nika and run it with the stand-in model (mock/echo).

```yaml
nika: ask
model: mock/echo
permits:
  tools: ["nika:prompt"]
tasks:
  approve:
    invoke:
      tool: "nika:prompt"
      args:
        mode: confirm
        message: "Delete the 2019 archive?"
  say:
    with:
      go: "${{ tasks.approve.output }}"
    when: ${{ with.go == true }}
    infer:
      prompt: "Say done."
      max_tokens: 20
```
