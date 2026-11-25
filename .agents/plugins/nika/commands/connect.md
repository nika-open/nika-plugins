---
description: Give a workflow a tool it lacks (an MCP server for a service or a need) — find the server, write its declaration and its permits, say where its key goes, then check
argument-hint: <service or need> [file.nika]
allowed-tools: Bash(nika check:*), Bash(nika catalog:*), Bash(nika explain:*), Bash(nika spec:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/nika-kit *), Read, Write, Edit, Glob
---

The person wants a workflow to use a service the builtins do not reach:
`$ARGUMENTS`. A new MCP server is a new effect: a program on their machine,
new hosts, maybe a billed account. So it is offered before it is written,
and the person says yes to the one you name.

**1 · Look at what is already there.** Does a builtin do it
(`nika catalog --tools`)? `nika:fetch` covers a plain HTTP API. Does the
project already declare a server that covers the need
(`.nika/mcp_servers.json`)? The cheapest tool is the one already granted.

**2 · Find the server.** Ask the binary whether it lists servers:
`"${CLAUDE_PLUGIN_ROOT}/bin/nika-kit" --has mcp-shelf` (without the kit's
scripts: look for `--mcp` in `nika catalog --help`).

- Exit 0: `nika catalog --mcp` prints the shelf. Pick the entry that fits
  the need and take its launch command, its key and its tools from there.
- Exit 1: this binary prints no such list. Take the launch command from the
  server's own documentation, which the person points you to or confirms.
  Do not write a package name or a launch command from memory.

Either way the server starts inside the sandbox of step 5. A documented
command that downloads the server when it starts does not work there: the
server is installed inside the project first, and the declaration starts
that copy.

When one key covers several needs (a hub that fronts many services), say so
in one line: fewer keys and one grant, against one more party that sees the
calls. The person chooses.

**3 · Offer before writing.** One message: which server, started by which
command, which of its tools the workflow will call, which hosts it must
reach, which key it needs and how that key will reach it. Wait for the yes.

**4 · Write the two parts.** The shapes are in the authoring skill's
`references/capabilities.md`, « MCP servers »; read them there, not from
memory.

- The declaration, in the project's `.nika/mcp_servers.json`, under its
  `servers` key (`{"mcp_servers_format": 1, "servers": {"<name>": {…}}}`):
  the server's name, its `command` and `args`, and its `network` arm. An absent arm
  denies the network; grant the list of hosts the server needs rather than
  `"allow"`.
- In the workflow, `permits.tools` for exactly the tools the tasks call,
  each by its name (`"mcp:<server>/<tool>"`), and nothing wider.

**5 · The sandbox and the key.** Measured on 0.125.0 with
`nika mcp approve`: a declared server starts inside a sandbox. It reads and
writes inside the project folder only (a file in the home folder or
anywhere else is refused), the network is denied unless the `network` arm
grants it, and its environment is reduced to `HOME`, `PATH` and `PWD`: a
key exported in the person's shell is not passed to it. A launcher that
resolves or installs the server outside the project when it starts (a
package runner with its cache in the home folder) fails there. The
declaration has no field that points at a secret store. That leaves two
routes for a key, and each exposes it:

- in the launch arguments: the value is then written in
  `.nika/mcp_servers.json`, copied into `.nika/mcp_pins.json` at approval,
  and shown in the machine's process list;
- in a file inside the project that the server reads: every workflow or
  tool granted that path can read it, and it is committed unless the
  project ignores it.

Say both plainly, with what each exposes, and let the person choose one or
refuse: a key that cannot reach the server on terms they accept is a reason
to stop here. The person puts the value in place. Never write it into the
declaration, a workflow or a message, and never move a key to another host
or store yourself.

**6 · Approving the tools is theirs.** `nika mcp approve <server>` starts
the server once, prints its tools and pins their definitions; the person
also says there which tools read private data and which send out
(`--reads-private`, `--sends-out`, `--no-role`). Show them the command.
They run it, and you never declare a role for them.

**7 · Check.** `nika check <file> --json --native-strict`. A workflow that
reads private files, takes in outside content and can send out answers
`NIKA-SEC-009`, and an MCP tool can be both outside content and a way out.
Say what the finding means in plain words and let the person decide between
dropping a read, splitting the job or a gate; do not add a gate on your
own (the authoring skill's `references/job-anatomy.md`, « Approve once,
then let it run »).

**8 · Say what the spending ceiling does not cover.** On 0.125.0 a call to
an MCP tool is not priced by the engine, so `--max-cost-usd` does not bound
it: if the service bills per call, that bill is outside the ceiling. Bound
a fan-out over a billed tool yourself (`for_each.max_items`, a small
`max_parallel`). Say this once, in one line, before the first run.

**9 · Hand over.** The server and how it starts, the hosts and tools
granted, how the key reaches it, what the ceiling does not cover, what the
person still has to run (`nika mcp approve`), then the verdict of
`nika check` on the file, quoted.
