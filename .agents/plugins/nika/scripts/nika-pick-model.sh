#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# nika-pick-model — choose a model route that works on THIS machine, so
# a person never meets "no server listening" on their first run.
#
# It prints ONE line: the flags to add to `nika run` / `nika check`
# (`--model <provider/model>` or `--access claude-code`), or, when nothing
# is ready, the shortest way to get a route. It reads the environment and
# probes the local Ollama port; it installs nothing and prints no key.
#
# Order: a provider key already exported · a running Ollama · the Claude
# Code seat (needs its ACP adapter) · nothing.
#
# Usage: nika-pick-model.sh            # exit 0 = a route was printed
#                                       # exit 1 = no route, advice printed
set -u

pick() {
  printf '%s\n' "$1"
  exit 0
}

# 1 · a key that is already in the environment (names only, never values)
[ -n "${ANTHROPIC_API_KEY:-}" ] && pick "--model anthropic/claude-haiku-5-5"
[ -n "${OPENAI_API_KEY:-}" ] && pick "--model openai/gpt-5-mini"
[ -n "${GEMINI_API_KEY:-}" ] && pick "--model gemini/gemini-2.5-flash"
[ -n "${MISTRAL_API_KEY:-}" ] && pick "--model mistral/mistral-small-latest"
[ -n "${GROQ_API_KEY:-}" ] && pick "--model groq/llama-3.1-8b-instant"
[ -n "${DEEPSEEK_API_KEY:-}" ] && pick "--model deepseek/deepseek-flash"

# 2 · a local Ollama that answers, with at least one model pulled
if command -v curl >/dev/null 2>&1; then
  tags="$(curl -fsS --max-time 1 http://127.0.0.1:11434/api/tags 2>/dev/null || true)"
  first="$(printf '%s' "$tags" | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')"
  [ -n "$first" ] && pick "--model ollama/$first"
fi

# 3 · the Claude Code seat, only when its ACP adapter is installed
if command -v claude >/dev/null 2>&1 && command -v claude-agent-acp >/dev/null 2>&1; then
  pick "--access claude-code"
fi

# 4 · nothing ready: say the shortest ways out, in plain words
echo "No model is ready on this machine. Pick one:"
if command -v claude >/dev/null 2>&1; then
  echo "  - use your Claude Code subscription: npm i -g @agentclientprotocol/claude-agent-acp"
fi
echo "  - use an API key: export ANTHROPIC_API_KEY=... (or OPENAI_API_KEY, GEMINI_API_KEY)"
echo "  - use a local model: install Ollama, then: ollama pull qwen3.5:4b"
echo "  - just rehearse the steps, with no real answer: --model mock/echo"
exit 1
