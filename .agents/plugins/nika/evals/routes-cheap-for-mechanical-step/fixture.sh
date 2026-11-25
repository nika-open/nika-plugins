#!/usr/bin/env bash
# Scaffold for the routes-cheap-for-mechanical-step case: a week of support
# tickets, one per line. The job has one mechanical step (a label out of
# three for each ticket) and one step where quality matters (a summary of
# the week's themes). The case measures that the two steps do not get the
# same model route, and that both names come from the binary's catalog.
set -eu
cat >tickets.txt <<'TXT'
I was charged twice for the March invoice.
The export button does nothing on Safari.
How do I add a second user to my account?
My card was declined but the order went through.
The app logs me out every ten minutes.
Can I change the billing date?
TXT
