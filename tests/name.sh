#!/bin/sh
# A seat by name alone, and turning handoffs on from it.
#
# "log-append.sh name <Codename>" writes seat.json with "mode": "name"
# and nothing else. At session start the hook greets the session by that
# name, says nothing about checkpoints, handoffs, the verifier or the stop
# phrase, and gives one line on how to turn handoffs on. The other hooks
# do nothing. "log-append.sh seat" with the same codename turns handoffs
# on and keeps the name. A project seated in full from the start is
# untouched by any of this.

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

title "A name and nothing else"
new_project name
printf 'x\n' > a.txt
commit_all "Initial commit" > /dev/null
seat=.succession/seat.json
log=.succession/log.jsonl

# start [compact]: the status hook as hooks.json runs it.
start() {
  OUT=$(CLAUDE_PROJECT_DIR="$PROJ" "$SH" "$SCRIPTS/session-start.sh" "$@" 2>&1 < /dev/null)
  RC=$?
}

# title_for <hook input>: what "session-start.sh title" prints, in TITLE.
title_for() {
  TITLE=$(printf '%s' "$1" | CLAUDE_PROJECT_DIR="$PROJ" "$SH" "$SCRIPTS/session-start.sh" title 2>&1)
  TITLE_RC=$?
}
INPUT_NEW='{"session_id":"abc123","transcript_path":"/nonexistent/transcript.jsonl","cwd":"/nonexistent","hook_event_name":"SessionStart","source":"startup","model":"some-model"}'
INPUT_NAMED='{"session_id":"abc123","transcript_path":"/nonexistent/transcript.jsonl","cwd":"/nonexistent","hook_event_name":"SessionStart","source":"resume","session_title":"my own name for it"}'

# lines_with <text> <needle>: how many lines of the text hold the needle.
lines_with() {
  printf '%s\n' "$1" | grep -c -F -- "$2"
}

# no_machinery <description>: nothing in OUT about the full seat.
no_machinery() {
  for nm_word in heckpoint 'Charter' 'charter' 'Lineage' 'Latest handoff' 'Verdict' 'verify' 'Stand down' '/succession:close' 'officeholder' 'WARNING'; do
    check "$1: says nothing of \"$nm_word\"" lacks "$OUT" "$nm_word"
  done
}

say "Seating by name alone."
run "log-append.sh name Sextant" "$SH" "$SCRIPTS/log-append.sh" name Sextant
check "exit 0" [ "$RC" -eq 0 ]
check "says the name" contains "$OUT" "Named: Sextant."
check "gives the one line on turning handoffs on" contains "$OUT" "Handoffs are off. To turn them on and keep the name Sextant, send /succession:seat."
check "seat.json is a plain file" plain_file "$seat"
check "seat.json is in name mode" grep -q '"mode": "name"' "$seat"
check "seat.json holds the name" grep -q '"codename": "Sextant"' "$seat"
check "seat.json holds no status, number or tenure" [ "$(grep -c '"status"\|"ordinal"\|"tenure"' "$seat")" -eq 0 ]
check "nothing else was written: no log, lineage, charter or tenure folder" \
  absent "$log" .succession/lineage.jsonl .succession/charter.md .succession/tenures
check "no lock is left behind" absent .succession/.lock .succession/.lock-clear .succession/seat.json.tmp

say "A codename that is not one is refused."
for badname in '' '7up' 'two words' 'trailing-' 'Abcdefghijabcdefghijabcdefghijabc'; do
  quiet "$SH" "$SCRIPTS/log-append.sh" name "$badname"
  check "refused: '$badname' (exit 2)" [ "$RC" -eq 2 ]
done
check "seat.json still holds Sextant" grep -q '"codename": "Sextant"' "$seat"

say "Session start greets the session by its name."
start
printf '%s\n' "$OUT" | sed 's/^/      /'
check "exit 0" [ "$RC" -eq 0 ]
check "tells the session its name" contains "$OUT" "You are Sextant in this project."
check "has it open its first reply with the name" contains "$OUT" "Open your first reply with one short line that says your name"
check "exactly one line says how to turn handoffs on" [ "$(lines_with "$OUT" "/succession:seat")" -eq 1 ]
check "and it is this line" contains "$OUT" "Handoffs are off. To turn them on and keep the name Sextant, send /succession:seat."
check "three lines in all" [ "$(printf '%s\n' "$OUT" | grep -c '')" -eq 3 ]
no_machinery "session start"
start compact
check "after a compaction: the name again" contains "$OUT" "You are Sextant in this project. Open your next reply"
check "after a compaction: the same one line on handoffs" [ "$(lines_with "$OUT" "/succession:seat")" -eq 1 ]
no_machinery "after a compaction"
title_for "$INPUT_NEW"
check "the session title is the name" [ "$TITLE_RC$TITLE" = '0{"hookSpecificOutput":{"hookEventName":"SessionStart","sessionTitle":"Sextant"}}' ]
title_for "$INPUT_NAMED"
check "a session that has a title of its own keeps it" [ "$TITLE_RC$TITLE" = "0" ]

say "Nothing of the checkpoint, handoff or stop machinery runs."
before=$(file_sum "$seat")
OUT=$(printf '%s' '{"session_id":"abc123","transcript_path":"/nonexistent/transcript.jsonl","cwd":"/nonexistent","permission_mode":"default","hook_event_name":"UserPromptSubmit","prompt":"Stand down, Sextant"}' \
  | CLAUDE_PROJECT_DIR="$PROJ" "$SH" "$SCRIPTS/stand-down.sh" 2>&1)
RC=$?
check "the prompt hook: exit 0, nothing printed, even for the stop phrase" [ "$RC$OUT" = "0" ]
OUT=$(printf '%s' '{"session_id":"abc123","hook_event_name":"PreCompact","trigger":"auto"}' \
  | CLAUDE_PROJECT_DIR="$PROJ" "$SH" "$SCRIPTS/compact-mark.sh" auto 2>&1)
RC=$?
check "the compaction hook: exit 0, nothing printed" [ "$RC$OUT" = "0" ]
check "neither hook wrote a log" absent "$log"
check "seat.json is as it was" [ "$(file_sum "$seat")" = "$before" ]
for ev in "checkpoint did-something" "close done" "vacate gone" "stand_down"; do
  # shellcheck disable=SC2086
  # (SC2086: the event and its one-word argument are split on purpose.)
  quiet "$SH" "$SCRIPTS/log-append.sh" $ev
  check "log-append.sh ${ev%% *} is refused (exit 5)" [ "$RC" -eq 5 ]
  check "and the refusal says how to turn handoffs on" contains "$OUT" "/succession:seat turns handoffs on and keeps the name."
done
check "still no log" absent "$log" .succession/lineage.jsonl .succession/tenures
check "seat.json is still as it was" [ "$(file_sum "$seat")" = "$before" ]

say "Running name again changes the name."
quiet "$SH" "$SCRIPTS/log-append.sh" name Compass
check "exit 0" [ "$RC" -eq 0 ]
start
check "the session is now Compass" contains "$OUT" "You are Compass in this project."
quiet "$SH" "$SCRIPTS/log-append.sh" name Sextant
check "and back to Sextant" [ "$RC" -eq 0 ]

say "Turning handoffs on keeps the name."
run "verify.sh" "$SH" "$SCRIPTS/verify.sh"
check "the verifier runs on a name-mode project: exit 0" [ "$RC" -eq 0 ]
run "log-append.sh seat Sextant" "$SH" "$SCRIPTS/log-append.sh" seat Sextant
check "exit 0" [ "$RC" -eq 0 ]
check "seated as Sextant-001" contains "$OUT" "Seated: Sextant-001 (tenure folder .succession/tenures/001-sextant)."
check "no warning" lacks "$OUT" "WARNING"
check "seat.json is a full seat now, without a mode" [ "$(grep -c '"mode"' "$seat")" -eq 0 ]
check "seat.json reads occupied for Sextant" grep -q '"codename": "Sextant"' "$seat"
check "the lineage has one seated record" [ "$(grep -c '"event":"seated"' .succession/lineage.jsonl)" -eq 1 ]
start
check "session start: the full status, with the same name" contains "$OUT" "Seat: occupied by Sextant-001"
check "session start: You are Sextant-001" contains "$OUT" "You are Sextant-001, the officeholder seated in this project."
check "session start: the name-mode lines are gone" lacks "$OUT" "Handoffs are off."
title_for "$INPUT_NEW"
check "the session title is Sextant-001" contains "$TITLE" '"sessionTitle":"Sextant-001"'
quiet "$SH" "$SCRIPTS/log-append.sh" checkpoint "a.txt is committed"
check "a checkpoint is taken now" [ "$RC" -eq 0 ]
quiet "$SH" "$SCRIPTS/log-append.sh" name Other
check "name is refused once handoffs are on (exit 5)" [ "$RC" -eq 5 ]
check "and seat.json is still the full seat" grep -q '"status": "occupied"' "$seat"

say "A name-mode seat.json next to a log is not trusted."
cp "$seat" "$WORK/seat.full"
printf '{\n  "mode": "name",\n  "codename": "Sextant",\n  "updated": "2026-01-01T00:00:00Z"\n}\n' > "$seat"
start
check "the seat reads as unknown" contains "$OUT" "Seat: unknown."
check "no name-mode greeting" lacks "$OUT" "Handoffs are off."
cp "$WORK/seat.full" "$seat"

say "A project seated in full from the start is as it was."
proj_named=$PROJ
new_project name-full
printf 'x\n' > a.txt
commit_all "Initial commit" > /dev/null
quiet "$SH" "$SCRIPTS/log-append.sh" seat Astrolabe
check "seated as Astrolabe-001" contains "$OUT" "Seated: Astrolabe-001"
check "its seat.json has no mode" [ "$(grep -c '"mode"' "$seat")" -eq 0 ]
start
check "session start gives the full status" contains "$OUT" "Seat: occupied by Astrolabe-001"
check "and the stop phrase" contains "$OUT" "Stand down, Astrolabe"
check "and nothing of name mode" lacks "$OUT" "Handoffs are off."
quiet "$SH" "$SCRIPTS/log-append.sh" name Astrolabe
check "name is refused in it (exit 5)" [ "$RC" -eq 5 ]
check "and says why" contains "$OUT" "already keeps handoffs"
if [ "$FAIL" -eq 0 ] && [ -z "${SUCCESSION_TEST_KEEP:-}" ]; then
  rm -rf "${proj_named%/project}"
fi

finish
