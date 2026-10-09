#!/bin/sh
# Replays, for a terminal recording of about half a minute, what was
# typed and answered in six real headless Claude Code sessions (Claude
# Code 2.1.295 on Linux, this plugin loaded with --plugin-dir, one
# throwaway git project). Nothing here is run: every reply below is the
# session's own text, copied, with Markdown's asterisks and backquotes
# taken off and cuts marked [...]. The lines in round brackets are ours.
# The time the model took to answer is left out.
#
#   asciinema rec --cols 92 --rows 34 --command "sh tests/recording/come-back.sh" come-back.cast
#
# The six sessions:
#   1-3  /succession:seat, /succession:seat Sextant, /succession:checkpoint
#        (one conversation, continued twice), then nothing more: no close
#   4    a new conversation: "Where were we?"
#   5    that conversation continued: /compact, then "Carry on."
#   6    after the tenure was closed by running the plugin's script on a
#        handoff written by hand, two of its claims false on purpose: a
#        new conversation, /succession:seat

PAUSE=${SUCCESSION_DEMO_PAUSE:-1}
B=$(printf '\033[1m')
D=$(printf '\033[2m')
R=$(printf '\033[0m')

# nap <tenths of a pause>
nap() {
  np=$(awk -v p="$PAUSE" -v n="$1" 'BEGIN { printf "%.2f", p * n / 10 }')
  sleep "$np" 2> /dev/null || sleep 1
}

ours() {
  printf '%s(%s)%s\n' "$D" "$1" "$R"
}

shell() {
  printf '\n%s$%s claude\n' "$D" "$R"
  nap 5
}

typed() {
  printf '%s> %s%s\n' "$B" "$1" "$R"
  nap 9
}

reply() {
  for rp_line in "$@"; do
    printf '%s\n' "${rp_line:+  $rp_line}"
  done
}

printf '%sSuccession%s: an officeholder comes back by name\n' "$B" "$R"
nap 8

shell
typed '/succession:seat Sextant'
reply "I'm seated as ${B}Sextant-001${R}. The script gave no WARNING: line. [...]"
nap 14
typed '/succession:checkpoint a.txt and b.txt are committed'
reply 'Sextant-001: checkpoint recorded at 2026-10-09T04:08:00Z in' \
  '.succession/tenures/001-sextant/checkpoints.md. [...]'
nap 14
ours 'the session ends here: no close, no handoff'
nap 16

shell
ours 'a new session; Claude Code reports its title as Sextant-001'
typed 'Where were we?'
reply "${B}I'm Sextant-001. My last checkpoint says a.txt and b.txt are committed.${R} [...]"
nap 30
typed '/compact'
typed 'Carry on.'
reply "I'm Sextant-001. My last checkpoint recorded that a.txt and b.txt are committed." \
  '' \
  'I re-read the charter and the checkpoint after the compaction. [...]'
nap 30

printf '\033[2J\033[H'
ours 'later the tenure is closed; two claims in its handoff are false on purpose'
shell
ours 'a new session: the successor'
typed '/succession:seat'
reply "Here is the verifier's complete output:" ''
nap 6
reply 'Succession verify: handoff of 001-sextant' \
  '' \
  'From handoff.md (the pointer in brackets was checked; the sentence under it was not):' \
  '  1. [pointer verified] commit:b05ac7a' \
  '     Added a.txt' \
  '  2. [pointer verified] file:b.txt@c880940' \
  '     b.txt is in the repository' \
  '  3. [pointer verified] log:8fef25cf3d21' \
  '     Checkpoint recorded after both files were committed'
nap 6
reply "  4. [${B}FAILED${R}] file:deploy.sh@c880940" \
  '     Added the deploy script' \
  '     -> no such file in that commit' \
  "  5. [${B}FAILED${R}] commit:0123456789abcdef0123456789abcdef01234567" \
  '     Fixed the flaky test' \
  '     -> no such commit in this repository' \
  '  6. [not checkable] none' \
  '     Told the owner about the staging deploy' \
  '     -> no pointer given; a script cannot check this'
nap 6
reply '' \
  'Log chain: intact (4 entries).' \
  'Handoff: unchanged since the close (its sha256 is the one in the close entry of the log).' \
  '[...]' \
  "${B}6 claims, 3 pointers verified, 2 failed, 1 not checkable.${R}"
nap 50
reply '[...]' \
  "Do you want to go on with the two failed claims on record? If so, I'll serve as" \
  'Astrolabe-002. To confirm, send /succession:seat Astrolabe.'
nap 40
# (An attribute reset that changes nothing on screen, so that the recording
# holds the last frame for the length of the pause above.)
printf '\033[0m'
