---
type: tool_used
tool: Bash
input_match: '"command"\s*:\s*"(?:\\.|[^"\\])*?(?<![\w.-])nika\\?["'']?(?:\s+run\b(?=\s+\S)|\s+\\?["'']?[^\s"''\\;&|]+\.nika\b)(?!(?:\\[^n]|[^;&|"\\\n])*(?:--dry-run|mock/echo|--help\b|\s-h\b))'
min: 0
max: 0
---
