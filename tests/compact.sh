#!/bin/sh
# The note a compaction leaves in the log.
#
# compact-mark.sh is the PreCompact hook. It adds one log entry when an
# officeholder holds the seat and does nothing otherwise. Whatever
# happens, it prints nothing on standard output and exits 0: Claude Code
# takes exit code 2 from this hook as "do not compact", and text on its
# standard output as an instruction for the summary.

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

title "Compaction"
new_project compact
printf 'x\n' > a.txt
commit_all "Initial commit" > /dev/null
log=.succession/log.jsonl
MARK=' Written by the plugin before Claude Code compacted the context, not by the officeholder.'

# mark <project folder> [<argument>...]: runs the hook the way hooks.json
# does, with the documented hook input on standard input. Leaves standard
# output in OUT, standard error in ERR and the exit code in RC.
mark() {
  mk_dir=$1
  shift
  OUT=$(printf '%s' '{"session_id":"abc123","transcript_path":"/nonexistent/transcript.jsonl","cwd":"/nonexistent","hook_event_name":"PreCompact","trigger":"manual","custom_instructions":null}' \
    | CLAUDE_PROJECT_DIR="$mk_dir" "$SH" "$SCRIPTS/compact-mark.sh" "$@" 2> "$WORK/mark.err")
  RC=$?
  ERR=$(cat "$WORK/mark.err")
}

# silent_ok <description>: no output of either kind, exit 0.
silent_ok() {
  check "$1: exit 0, nothing printed" [ "$RC$OUT$ERR" = "0" ]
}

entries() {
  if [ -f "$log" ]; then
    grep -c '' "$log"
  else
    printf '0\n'
  fi
}

say "Where there is nothing to note, the hook does nothing."
mkdir "$WORK/plain"
mark "$WORK/plain" manual
silent_ok "a folder with no repository"
mark "$PROJ" manual
silent_ok "a repository without .succession"
check "and no .succession folder was made" absent .succession

quiet "$SH" "$SCRIPTS/log-append.sh" seat Sextant
quiet "$SH" "$SCRIPTS/log-append.sh" checkpoint "a.txt is committed"
printf '\n## A note\n\n- CLAIM [none] by hand\n' >> .succession/tenures/001-sextant/checkpoints.md

say "A seat is occupied: one entry, and nothing else changes."
seat_before=$(file_sum .succession/seat.json)
lineage_before=$(file_sum .succession/lineage.jsonl)
note_before=$(file_sum .succession/tenures/001-sextant/checkpoints.md)
n=$(entries)
mark "$PROJ" manual
silent_ok "a manual compaction"
check "one entry was added" [ "$(entries)" -eq $((n + 1)) ]
last=$(tail -n 1 "$log")
printf '      %s\n' "$(printf '%s' "$last" | cut -c 1-190)"
check "it is of the type checkpoint, for the seated tenure, with the fixed text" contains "$last" "\"type\":\"checkpoint\",\"tenure\":\"001-sextant\",\"data\":\"Context compacted (manual).$MARK\",\"prev\":\""
mark "$PROJ" auto
silent_ok "an automatic compaction"
check "one more entry" [ "$(entries)" -eq $((n + 2)) ]
check "it says auto" contains "$(tail -n 1 "$log")" "\"data\":\"Context compacted (auto).$MARK\",\"prev\":\""
check "seat.json is as it was" [ "$(file_sum .succession/seat.json)" = "$seat_before" ]
check "lineage.jsonl is as it was" [ "$(file_sum .succession/lineage.jsonl)" = "$lineage_before" ]
check "the checkpoint note is as it was" [ "$(file_sum .succession/tenures/001-sextant/checkpoints.md)" = "$note_before" ]
check "no lock is left behind" absent .succession/.lock .succession/.lock-clear
quiet "$SH" "$SCRIPTS/verify.sh" --draft --checkpoints
printf '%s\n' "$OUT" | grep 'Log chain' | sed 's/^/      /'
check "the chain checks out with the two notes in it" contains "$OUT" "Log chain: intact ($((n + 2)) entries)."
verdict "compact: $(last_line "$OUT")"
mkdir sub
mark "$PROJ/sub" manual
silent_ok "from a folder inside the repository"
check "one more entry" [ "$(entries)" -eq $((n + 3)) ]
rmdir sub

say "Only the two words that Claude Code's matchers pass are acted on."
n=$(entries)
mark "$PROJ"
silent_ok "no argument"
mark "$PROJ" 'manual"; rm -rf x'
silent_ok "an argument that is neither word"
mark "$PROJ" compact
silent_ok "another word"
check "nothing was added" [ "$(entries)" -eq "$n" ]

say "The script the hook calls says what it wrote, and takes nothing else."
run "log-append.sh compact manual" "$SH" "$SCRIPTS/log-append.sh" compact manual
check "exit 0" [ "$RC" -eq 0 ]
check "it names the officeholder" contains "$OUT" "Compaction noted for Sextant-001."
check "the entry's time is printed under its hash, and is the ts in the log" entry_time_ok "$OUT" "$log"
quiet "$SH" "$SCRIPTS/log-append.sh" compact sometimes
check "another word is a usage error (exit 2)" [ "$RC" -eq 2 ]
quiet "$SH" "$SCRIPTS/log-append.sh" compact
check "no word is a usage error (exit 2)" [ "$RC" -eq 2 ]

say "A lock that stays held: the compaction is not held up."
# The lock names this test, which is alive. The note cannot be written.
n=$(entries)
mkdir .succession/.lock
printf '%s\n' "$$" > .succession/.lock/pid
t0=$(date +%s)
mark "$PROJ" auto
took=$(($(date +%s) - t0))
printf '      a lock held by a live process: the hook answered in %s s\n' "$took"
printf '      %s\n' "$(printf '%s' "$ERR" | cut -c 1-220)"
check "the hook answered in under 8 seconds" [ "$took" -lt 8 ]
check "exit 0 all the same" [ "$RC" -eq 0 ]
check "nothing on standard output" [ -z "$OUT" ]
check "one line on standard error, saying that the compaction was not noted" \
  [ "$(printf '%s\n' "$ERR" | grep -c '')$(printf '%s\n' "$ERR" | grep -c '^succession: the compaction (auto) was not noted in \.succession/log\.jsonl: another Succession write is still in progress')" = "11" ]
check "nothing was added" [ "$(entries)" -eq "$n" ]
check "the lock is still the live writer's" [ "$(cat .succession/.lock/pid)" = "$$" ]
rm -f .succession/.lock/pid
rmdir .succession/.lock

say "A log that cannot be written to: the same."
if [ -w / ] || ! chmod a-w "$log" 2> /dev/null || [ -w "$log" ]; then
  printf '      skipped: this user can write to a read-only file here\n'
else
  mark "$PROJ" manual
  check "exit 0" [ "$RC" -eq 0 ]
  check "nothing on standard output" [ -z "$OUT" ]
  check "one line on standard error" [ "$(printf '%s\n' "$ERR" | grep -c '^succession: the compaction (manual) was not noted')" -eq 1 ]
  check "nothing was added" [ "$(entries)" -eq "$n" ]
  check "no lock is left behind" absent .succession/.lock .succession/.lock-clear
fi
chmod u+w "$log" 2> /dev/null

say "Stood down, and vacant: nothing is noted."
quiet "$SH" "$SCRIPTS/log-append.sh" stand_down
n=$(entries)
mark "$PROJ" manual
silent_ok "stood down"
check "nothing was added" [ "$(entries)" -eq "$n" ]
quiet "$SH" "$SCRIPTS/log-append.sh" compact manual
check "the script refuses as well (exit 5)" [ "$RC" -eq 5 ]
printf '# Handoff\n\n- CLAIM [none] nothing\n' > .succession/tenures/001-sextant/handoff.md
quiet "$SH" "$SCRIPTS/log-append.sh" close "Closed" "None."
n=$(entries)
mark "$PROJ" auto
silent_ok "vacant"
check "nothing was added" [ "$(entries)" -eq "$n" ]

say "What the notes leave for the successor's check."
quiet "$SH" "$SCRIPTS/verify.sh"
printf '%s\n' "$OUT" | tail -n 3 | sed 's/^/      /'
check "the handoff is verified as before: 1 claim, not checkable" contains "$(last_line "$OUT")" "1 claims, 0 pointers verified, 0 failed, 1 not checkable."
check "the chain is intact" contains "$OUT" "Log chain: intact"
verdict "compact successor: $(last_line "$OUT")"

say "The hook's standard input is not waited for."
quiet "$SH" "$SCRIPTS/log-append.sh" seat Astrolabe
n=$(entries)
OUT=$(CLAUDE_PROJECT_DIR="$PROJ" "$SH" "$SCRIPTS/compact-mark.sh" manual < /dev/null 2>&1)
check "with nothing on standard input the note is written" [ "$?$OUT$(entries)" = "0$((n + 1))" ]

finish
