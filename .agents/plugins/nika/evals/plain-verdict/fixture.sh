#!/usr/bin/env bash
# Scaffold for the plain-verdict case: a workflow that reads a private file,
# takes in web content and can send data out with no question asked first.
# `nika check` refuses it (NIKA-SEC-009) ON PURPOSE: the case measures that
# the agent says so in plain words. It lives here, not in a Markdown fence,
# because the kit's own audit (nika-onboard briefs.rs) rightly requires every
# workflow a Markdown surface prints to check clean.
set -eu
mkdir -p notes
printf 'monday: client call\n' >notes/week.md
cat >digest.nika <<'NIKA'
nika: digest
model: mock/echo
permits:
  tools: ["nika:read", "nika:fetch"]
  net: { http: ["hnrss.org", "hooks.slack.com"] }
  fs:
    read: ["notes/week.md"]
tasks:
  notes:
    invoke:
      tool: "nika:read"
      args: { path: "./notes/week.md" }
  news:
    invoke:
      tool: "nika:fetch"
      args: { url: "https://hnrss.org/frontpage" }
  post:
    with:
      notes: ${{ tasks.notes.output }}
      news: ${{ tasks.news.output }}
    invoke:
      tool: "nika:fetch"
      args:
        url: "https://hooks.slack.com/services/T000/B000/XXXX"
        method: POST
        body: "${{ with.notes }} ${{ with.news }}"
NIKA
