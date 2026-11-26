#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# nika-pick-model — choose a model route that works on THIS machine, so
# a person never meets "no server listening" on their first run.
#
# It prints ONE line: the flags to add to `nika run` / `nika check`
# (`--model <provider/model>` or `--access claude-code`), or, when nothing
# is ready, the shortest way to get a route. It reads the environment and
# probes the local Ollama port; it installs nothing and prints no key. The
# model of a keyed route is the provider's cheaper tier in `nika catalog`.
#
# Order: a provider key already exported · a running Ollama · the Claude
# Code seat (needs its ACP adapter) · nothing.
#
# Usage: nika-pick-model.sh            # exit 0 = a route was printed
#                                       # exit 1 = no route, advice printed

# >>> nika-clean-path: every kit hook and helper opens with this same block,
# before it starts any other program (a test keeps the copies identical).
# Hosts start hooks in the open project, and the PATH can name folders the
# repository holds: a relative entry (".", "bin", "node_modules/.bin", the
# empty one) resolves there, and an absolute one can lead there too. Only
# the absolute entries whose real folder (cd -P) lies outside the project
# are kept, as those real folders. The project is each of
# CLAUDE_PROJECT_DIR, CURSOR_PROJECT_DIR and the working folder, with the
# git work tree around each (the nearest folder above holding .git), but
# never the home or a folder above it. A function of builtins, run once in
# a subshell (bash 3.2 cannot parse a case inside $(...)): nothing runs
# before the PATH is set. The kit's manifests start this script with
# /bin/bash -p (see the README for what that does and does not cover).
nika_clean_path() {
  local here dir top root home kept rest
  here="${PWD:-}"
  set --
  home=/
  case "${HOME:-}" in
    /*) cd -P -- "$HOME" 2>/dev/null && home="$PWD" ;;
  esac
  for dir in "${CLAUDE_PROJECT_DIR:-}" "${CURSOR_PROJECT_DIR:-}" "$here"; do
    case "$dir" in
      /*) cd -P -- "$dir" 2>/dev/null || continue ;;
      *) continue ;;
    esac
    top="$PWD"
    while [ -n "$top" ] && [ ! -e "$top/.git" ]; do
      top="${top%/*}"
    done
    for root in "$PWD" "$top"; do
      case "$root" in
        '' | /) continue ;;
      esac
      case "$home/" in
        "$root"/*) continue ;;
      esac
      set -- "$@" "$root"
    done
  done
  kept=""
  rest="${PATH:-}"
  while [ -n "$rest" ]; do
    dir="${rest%%:*}"
    case "$rest" in
      *:*) rest="${rest#*:}" ;;
      *) rest="" ;;
    esac
    case "$dir" in
      /*) cd -P -- "$dir" 2>/dev/null || continue ;;
      *) continue ;;
    esac
    for root; do
      case "$PWD/" in
        "$root"/*) continue 2 ;;
      esac
    done
    kept="${kept:+$kept:}$PWD"
  done
  printf '%s' "$kept"
}
nika_path="$(nika_clean_path)"
unset -f nika_clean_path
PATH="${nika_path:-/usr/bin:/bin}"
export PATH
unset nika_path
# nika_on_path: the nika this PATH names, as an absolute path, when there is
# one. `type -P` searches the PATH alone: a function or an alias named nika
# never answers.
# shellcheck disable=SC2329 # not every script asks for nika
nika_on_path() {
  local bin
  bin="$(type -P nika)" || return 1
  case "$bin" in
    /*) printf '%s\n' "$bin" ;;
    *) return 1 ;;
  esac
}
# <<< nika-clean-path

set -u

pick() {
  printf '%s\n' "$1"
  exit 0
}

# The model name comes from the binary's own catalog (the provider's cheaper
# tier), so a release that renames a model does not leave a dead name here.
# The second argument is used only when no binary or no python3 answers.
here="$(cd "$(dirname "$0")" && pwd)"
catalog=""
if command -v python3 >/dev/null 2>&1; then
  if [ -x "$here/../bin/nika-kit" ]; then
    nika="$(bash -p "$here/../bin/nika-kit" --path "$PWD" 2>/dev/null || true)"
  else
    case "${NIKA_BIN:-}" in
      /*) nika="$NIKA_BIN" ;;
      *) nika="$(nika_on_path 2>/dev/null || true)" ;;
    esac
  fi
  [ -n "${nika:-}" ] && catalog="$("$nika" catalog --json 2>/dev/null || true)"
fi
route() { # route <provider id> <name when the catalog does not answer>
  local found=""
  if [ -n "$catalog" ]; then
    found="$(printf '%s' "$catalog" | python3 -I -c 'import json, sys
try:
    rows = json.load(sys.stdin).get("providers", [])
except Exception:
    rows = []
for row in rows:
    if row.get("id") == sys.argv[1]:
        print(row.get("cheap_model") or row.get("default_model") or "")' "$1" 2>/dev/null)"
  fi
  pick "--model $1/${found:-$2}"
}

# 1 · a key that is already in the environment (names only, never values)
[ -n "${ANTHROPIC_API_KEY:-}" ] && route anthropic claude-haiku-5-5
[ -n "${OPENAI_API_KEY:-}" ] && route openai gpt-5-mini
[ -n "${GEMINI_API_KEY:-}" ] && route gemini gemini-2.5-flash
[ -n "${MISTRAL_API_KEY:-}" ] && route mistral mistral-small-latest
[ -n "${GROQ_API_KEY:-}" ] && route groq llama-3.1-8b-instant
[ -n "${DEEPSEEK_API_KEY:-}" ] && route deepseek deepseek-flash

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
