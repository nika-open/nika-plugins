---
type: tool_used
tool: Bash
input_match: '(?:>>?\s*|(?<![\w-])tee\s+(?:-a\s+)?|(?<![\w-])sed\s+-i(?:\\[^n]|[^;&|"\\\n])*\s)\\?["'']?[^\s"''\\;&|>]*triage\.nika|(?<![\w-])(?:cp|mv)\s+(?:\\[^n]|[^;&|"\\\n])*\s\\?["'']?[^\s"''\\;&|>]*triage\.nika\\?["'']?\s*(?:[;&|"]|\\n|$)'
min: 0
max: 0
---
