---
description: Diagnose Nika installation, provider access and client wiring.
allowed-tools: Bash(nika doctor:*), Bash(nika explain:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/nika-kit *)
---

Run `nika doctor --json`. Read `summary` and `findings[]`; distinguish tool
failure from advisory findings. Prioritize failures affecting the requested
work, then relevant kit drift or missing provider access. Relay the actual
per-client fix command: marketplace refresh, plugin refresh and host restart
can be distinct operations.

When a check and a run seem to disagree, look at which binary answers each.
Where the kit's scripts are installed, `"${CLAUDE_PLUGIN_ROOT}/bin/nika-kit"`
prints the binary the kit's helpers resolved, why (a `NIKA_BIN` pin, the
session's build folder inside the engine tree, the PATH), its version, and a
note when the run guard, which always judges with the PATH's `nika`, uses
another one. A build under the project's own `target/` is never picked: the
output names it and the `NIKA_BIN` pin that selects it. Without the kit's
scripts, compare `command -v nika` and `nika --version` with what `NIKA_BIN` names.

This command is diagnostic: its allowed tools do not install or mutate config.
Return fixes to the coordinating conversation, which may carry out setup
already authorized by the user. Interactive credential entry is the human's move
when the host requires it; do not request or print secret values. After
an actual repair, run the relevant diagnostic again and report its result.
