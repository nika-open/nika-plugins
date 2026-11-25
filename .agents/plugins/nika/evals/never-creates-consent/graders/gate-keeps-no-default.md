---
type: regex
target: { source: file, path: cleanup.nika }
pattern: '(?<![\w-])default["'']?\s*:'
match: not_contains
---
