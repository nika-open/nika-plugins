#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# intent-hint — UserPromptSubmit: notice a REPEATABLE request (a schedule,
# a batch, "do it again") and hand the agent one short hint, so Nika is
# offered on intent, not on the word "Nika". No model call. A prompt that
# does not match costs a few milliseconds and starts nothing else; a prompt
# that matches is read once by the engine (nika-intent.py --from-hook).
#
# Laws: at most ONE hint per session (a marker under the plugin data dir,
# or TMPDIR) · silence ({}-free: no output at all) when nothing matches ·
# never blocks a prompt · exit 0 always.
set -u
input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0

lower="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')"
# A slash command or a prompt already about nika needs no hint.
case "$lower" in *'"prompt":"/'* | *nika*) exit 0 ;; esac

pattern='every (day|week|month|morning|evening|hour|monday|tuesday|wednesday|thursday|friday|saturday|sunday)|each (day|week|month|morning)|daily|weekly|monthly|on a schedule|cron|for each (file|page|row|url|item|document|image|ticket|customer)|for every (file|page|row|url|item|document|image)|in bulk|batch of|do the same (again|as|for)|same thing (again|every)|run (it|this) again|tous les (jours|matins|soirs|mois|lundis|mardis|mercredis|jeudis|vendredis|samedis|dimanches)|toutes les (semaines|heures|nuits)|chaque (jour|semaine|mois|matin|lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)|pour chaque (fichier|page|ligne|url|document|image|ticket|client)|par lot|en lot|refais (pareil|la meme|la même)|comme la derni(e|è)re fois|a chaque fois|à chaque fois'
printf '%s' "$lower" | grep -Eq "$pattern" || exit 0

session="$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/' | tr -cd 'A-Za-z0-9_-')"
dir="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}"
marker="$dir/nika-intent-${session:-nosession}"
[ -e "$marker" ] && exit 0
mkdir -p "$dir" 2>/dev/null && : >"$marker" 2>/dev/null

# The engine reads a bounded sentence itself, with no model call, in about
# 15 ms. When it can, hand the agent that reading (pieces, schedule,
# questions) instead of a generic nudge. The helper works in a scratch
# folder: a hint never leaves a .nika/ folder in somebody's project.
if command -v nika >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  here="$(cd "$(dirname "$0")" && pwd)"
  reading="$(printf '%s' "$input" | "$here/nika-intent.py" --from-hook 2>/dev/null || true)"
  if [ -n "$reading" ]; then
    printf '%s\n' "$reading"
    exit 0
  fi
fi

printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"This request looks repeatable (a schedule, a batch, or doing the same thing again). If running it again later would help the user, offer ONCE to keep it as a checked Nika workflow (skill nika-running): say in plain words what it would read, what it could reach and what it could cost, and ask before creating any file. If they decline, do the task normally and do not offer again in this session."}}'
exit 0
