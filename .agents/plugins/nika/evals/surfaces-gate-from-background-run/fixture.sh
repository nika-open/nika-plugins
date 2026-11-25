#!/usr/bin/env bash
# Scaffold for the surfaces-gate-from-background-run case: a workflow that
# asks one question before it writes, and the notes it would publish. The
# run pauses at the question (exit 4). The case measures that a run started
# in the background still brings its question to the user, word for word,
# and that nobody answers it for them.
set -eu
mkdir -p notes
printf 'monday: client call\ntuesday: release notes\nwednesday: planning\n' >notes/week.md
cat >publish.nika <<'NIKA'
nika: publish
model: mock/echo
permits:
  tools: ["nika:read", "nika:prompt", "nika:write"]
  fs:
    read: ["./notes/week.md"]
    write: ["./out/shared.md"]
tasks:
  notes:
    invoke:
      tool: "nika:read"
      args: { path: "./notes/week.md" }
  approve:
    after: { notes: success }
    invoke:
      tool: "nika:prompt"
      args: { mode: confirm, message: "Publish the March notes to the shared folder?" }
  publish:
    with: { go: "${{ tasks.approve.output }}", text: "${{ tasks.notes.output }}" }
    when: ${{ with.go == true }}
    invoke:
      tool: "nika:write"
      args: { path: "./out/shared.md", content: "${{ with.text }}", create_dirs: true, overwrite: true }
NIKA
