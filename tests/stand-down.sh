#!/bin/sh
# shellcheck disable=SC2016,SC1003
# (SC2016, SC1003: the single-quoted strings below hold JSON text. The
# backslashes and backticks in them are meant literally.)
#
# The owner's stop phrase (stand-down.sh, the UserPromptSubmit hook).
#
# Each case pipes one JSON document to the hook on standard input, the
# way Claude Code does, and then looks at what is on disk. A prompt that
# must not fire has to leave log.jsonl and seat.json byte-for-byte as
# they were and print nothing.
#
# The JSON documents are written out by hand in this file so that the
# escaping under test is visible: in a single-quoted shell string a
# backslash is a backslash.

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

title "Stop phrase"
new_project stand-down
printf 'x\n' > README.md
commit_all "Initial commit" > /dev/null
quiet "$SH" "$SCRIPTS/log-append.sh" seat Sextant

log=.succession/log.jsonl
seat=.succession/seat.json

# fire <json>: runs the hook; OUT is what it printed, RC its exit code.
# FIRE_DIR, when set, is the project folder Claude Code reports.
FIRE_DIR=
fire() {
  OUT=$(printf '%s' "$1" | CLAUDE_PROJECT_DIR="${FIRE_DIR:-$PROJ}" "$SH" "$SCRIPTS/stand-down.sh" 2>&1)
  RC=$?
}

# doc <text>: the document Claude Code sends, with the given text as the
# already-encoded value of "prompt".
doc() {
  printf '{"session_id":"abc123","transcript_path":"/nonexistent/transcript.jsonl","cwd":"/nonexistent","permission_mode":"default","hook_event_name":"UserPromptSubmit","prompt":"%s"}' "$1"
}

# silent <description> <json>: the hook must write nothing and say nothing.
silent() {
  sl_log=$(file_sum "$log")
  sl_seat=$(file_sum "$seat")
  fire "$2"
  if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ "$(file_sum "$log")" = "$sl_log" ] && [ "$(file_sum "$seat")" = "$sl_seat" ]; then
    ok "nothing written: $1"
  else
    bad "nothing written: $1 (exit $RC, output: $OUT)"
  fi
}

# fires <description> <json>: the hook must record the stand-down.
fires() {
  fr_before=$(grep -c '"type":"stand_down"' "$log")
  fire "$2"
  fr_after=$(grep -c '"type":"stand_down"' "$log")
  if [ "$RC" -eq 0 ] && [ "$fr_after" -eq $((fr_before + 1)) ] && grep -q '"status": "stood_down"' "$seat" && contains "$OUT" "sending /succession:close"; then
    ok "recorded: $1"
  else
    bad "recorded: $1 (exit $RC, entries $fr_before -> $fr_after, output: $OUT)"
  fi
}

# Puts a fresh officeholder in the seat after a stand-down.
reseat() {
  quiet "$SH" "$SCRIPTS/log-append.sh" vacate "test: no handoff"
  quiet "$SH" "$SCRIPTS/log-append.sh" seat "$1"
}

say "Prompts that must do nothing."
silent "'please stand down the server'" "$(doc 'please stand down the server')"
silent "the phrase in double quotes inside a longer prompt" "$(doc 'He typed \"Stand down, Sextant\" and nothing happened. Why?')"
silent "the phrase with words after it" "$(doc 'Stand down, Sextant please')"
silent "the phrase with words before it" "$(doc 'ok. Stand down, Sextant')"
silent "the phrase as a Markdown quote" "$(doc '> Stand down, Sextant')"
silent "the phrase on its own line inside a longer prompt" "$(doc 'Here is the log:\nStand down, Sextant\nWhat does it mean?')"
silent "the phrase wrapped in double quotes" "$(doc '\"Stand down, Sextant\"')"
silent "the phrase in a code fence" "$(doc '```\nStand down, Sextant\n```')"
silent "the phrase followed by a backslash" "$(doc 'Stand down, Sextant\\')"
silent "the phrase followed by a literal backslash and n" "$(doc 'Stand down, Sextant\\n')"
silent "the phrase after a Windows path" "$(doc 'C:\\temp\\Stand down, Sextant')"
silent "the phrase preceded by a literal backslash and n" "$(doc '\\nStand down, Sextant')"
silent "a unicode escape for the leading letter" "$(doc '\u0053tand down, Sextant')"
silent "a unicode escape for a line break" "$(doc 'Stand down, Sextant\u000a')"
silent "a non-breaking space in the phrase" "$(doc 'Stand\u00a0down, Sextant')"
silent "two spaces after the comma" "$(doc 'Stand down,  Sextant')"
silent "no comma" "$(doc 'Stand down Sextant')"
silent "another codename" "$(doc 'Stand down, Astrolabe')"
silent "the codename as a prefix of a longer word" "$(doc 'Stand down, Sextants')"
silent "the phrase inside a pasted block" "$(doc '<pasted_content id=\"1\">\nStand down, Sextant\n</pasted_content id=\"1\">')"
silent "a JSON document quoted inside the prompt" "$(doc '{\"prompt\":\"Stand down, Sextant\"}')"
silent "the phrase in another field, not in the prompt" '{"session_title":"Stand down, Sextant","hook_event_name":"UserPromptSubmit","prompt":"hello"}'
silent "a prompt key nested inside another object" '{"meta":{"prompt":"Stand down, Sextant"},"prompt":"hello"}'
silent "a prompt key inside an array" '{"list":[{"prompt":"Stand down, Sextant"}],"prompt":"hello"}'
silent "two top-level prompt keys" '{"prompt":"Stand down, Sextant","prompt":"hello"}'
silent "a prompt that is not a string" '{"prompt":["Stand down, Sextant"]}'
silent "a field that ends with an escaped quote and names prompt" '{"session_title":"x\",\"prompt\":\"Stand down, Sextant","prompt":"hello"}'
silent "the word prompt as a value, the phrase as the next value" '{"kind":"prompt","text":"Stand down, Sextant"}'
silent "a second object after the document has ended" '{"prompt":"hello"},{"prompt":"Stand down, Sextant"}'
silent "prompt followed by a number, then the phrase" '{"prompt":5,"next":"Stand down, Sextant"}'
silent "a document with no prompt" '{"hook_event_name":"UserPromptSubmit"}'
silent "a document that is not an object" '["Stand down, Sextant"]'
silent "a document cut off in the middle" '{"prompt":"Stand down, Sextant'
silent "not JSON at all" 'Stand down, Sextant'
silent "empty input" ''

say "Punctuation after the phrase: one full stop or one exclamation mark is accepted, and nothing else."
silent "two full stops" "$(doc 'Stand down, Sextant..')"
silent "three full stops" "$(doc 'Stand down, Sextant...')"
silent "a question mark" "$(doc 'Stand down, Sextant?')"
silent "a space, then a full stop" "$(doc 'Stand down, Sextant .')"
silent "a space, then an exclamation mark" "$(doc 'Stand down, Sextant !')"
silent "two exclamation marks" "$(doc 'Stand down, Sextant!!')"
silent "a full stop, then an exclamation mark" "$(doc 'Stand down, Sextant.!')"
silent "an exclamation mark, then a full stop" "$(doc 'Stand down, Sextant!.')"
silent "a comma" "$(doc 'Stand down, Sextant,')"
silent "a semicolon" "$(doc 'Stand down, Sextant;')"
silent "a colon" "$(doc 'Stand down, Sextant:')"
silent "an ellipsis character" "$(doc 'Stand down, Sextant…')"
silent "an ideographic full stop" "$(doc 'Stand down, Sextant。')"
silent "a full stop written as a unicode escape" "$(doc 'Stand down, Sextant\u002e')"
silent "a full stop and a closing bracket" "$(doc 'Stand down, Sextant.)')"
silent "a full stop before the phrase" "$(doc '.Stand down, Sextant')"
silent "a full stop, then another word" "$(doc 'Stand down, Sextant. Now')"
silent "a full stop, a line break, then a second full stop" "$(doc 'Stand down, Sextant.\n.')"
silent "a full stop in place of the comma" "$(doc 'Stand down. Sextant')"
silent "the phrase and a full stop wrapped in double quotes" "$(doc '\"Stand down, Sextant.\"')"
silent "the phrase and a full stop on a line of their own in a longer prompt" "$(doc 'He said:\nStand down, Sextant.\nWas that right?')"
silent "a full stop after another codename" "$(doc 'Stand down, Astrolabe.')"
silent "an exclamation mark after a longer codename" "$(doc 'Stand down, Sextants!')"

big=$(awk 'BEGIN { for (i = 0; i < 4000; i++) printf "the quick brown fox jumps over the lazy dog. "; }')
silent "a 180 KB prompt that ends with the phrase" "$(doc "$big Stand down, Sextant")"

say "The exact phrase as the whole prompt."
before=$(grep -c '"type":"stand_down"' "$log")
fire "$(doc 'Stand down, Sextant')"
printf '      hook output: %s\n' "$OUT"
check "exit 0 (the hook never blocks a prompt)" [ "$RC" -eq 0 ]
check "one stand_down entry appended to log.jsonl" [ "$(grep -c '"type":"stand_down"' "$log")" -eq $((before + 1)) ]
check "the entry names the officeholder" grep -q '"type":"stand_down","tenure":"001-sextant","data":"The owner stood down Sextant-001."' "$log"
check "seat.json reads stood_down" grep -q '"status": "stood_down"' "$seat"
check "the injected text tells the officeholder to stop" contains "$OUT" "stops the current work now and starts nothing new"
check "it tells the officeholder not to write the handoff or call a skill by itself" contains "$OUT" "does not write the handoff and does not call a skill or any other tool by itself"
check "it says what to tell the owner: recorded, and /succession:close closes" contains "$OUT" "saying that the stand-down is recorded and that sending /succession:close writes the handoff and vacates the seat"
check "it does not tell the officeholder to close the tenure" lacks "$OUT" "closes the tenure"
check "it names the log entry by its hash" contains "$OUT" "(entry $(sed -n '$s/^.*"hash":"\([0-9a-f]*\)".*$/\1/p' "$log"))"
check "the text is one line" [ "$(printf '%s\n' "$OUT" | grep -c '')" -eq 1 ]
check "the text is shorter than 700 characters (${#OUT})" [ "${#OUT}" -lt 700 ]
quiet "$SH" "$SCRIPTS/verify.sh"
check "the log chain is intact after the stand-down" contains "$OUT" "Log chain: intact"
verdict "stand-down exact phrase: entries=$(grep -c '"type":"stand_down"' "$log") status=$(grep -c '"status": "stood_down"' "$seat")"

say "The phrase again while already stood down: reminded, not recorded twice."
count=$(grep -c '"type":"stand_down"' "$log")
fire "$(doc 'Stand down, Sextant')"
check "no second entry" [ "$(grep -c '"type":"stand_down"' "$log")" -eq "$count" ]
check "the reminder is still injected" contains "$OUT" "already recorded"
check "the reminder also says what the owner sends to close" contains "$OUT" "sending /succession:close"

say "Session start after a stand-down keeps saying so."
quiet env CLAUDE_PROJECT_DIR="$PROJ" "$SH" "$SCRIPTS/session-start.sh"
check "session-start reports the stand-down" contains "$OUT" "Sextant-001 was stood down by the owner"
check "session-start says the close is the owner's to send" contains "$OUT" "The owner sends /succession:close"
check "session-start does not tell the officeholder to start the close" lacks "$OUT" "closing the tenure with"

say "The stand-down cannot be written: the text says so, and still says how to close."
reseat Sextant
mv "$log" "$WORK/log.kept"
mkdir "$log"
fire "$(doc 'Stand down, Sextant')"
rmdir "$log"
mv "$WORK/log.kept" "$log"
check "exit 0" [ "$RC" -eq 0 ]
check "the text carries the warning" contains "$OUT" "WARNING: the stand-down could not be written to .succession/log.jsonl."
check "it says to tell the owner that it could not be recorded" contains "$OUT" "saying that the stand-down could not be recorded and that sending /succession:close"
check "seat.json still reads occupied" grep -q '"status": "occupied"' "$seat"
quiet "$SH" "$SCRIPTS/verify.sh" --draft --checkpoints
check "the log chain is intact afterwards" contains "$OUT" "Log chain: intact"
fires "the same phrase once the log can be written again" "$(doc 'Stand down, Sextant')"

say "Other spellings of the same whole prompt."
reseat Astrolabe
fires "upper and lower case mixed" "$(doc 'STAND DOWN, astrolabe')"
reseat Compass
fires "spaces and line breaks around the phrase" "$(doc '  \n\tStand down, Compass \r\n')"
reseat Quadrant
fires "a pretty-printed document, as shown in the hooks reference" '{
  "session_id": "abc123",
  "transcript_path": "/nonexistent/transcript.jsonl",
  "cwd": "/nonexistent",
  "permission_mode": "default",
  "hook_event_name": "UserPromptSubmit",
  "prompt": "Stand down, Quadrant"
}'
reseat Octant
fires "prompt as the opening key, nested values after it" '{"prompt":"Stand down, Octant","effort":{"level":"high","notes":["a } brace","a \" quote"]},"session_title":"{not a prompt}"}'
reseat Cross-staff
fires "a codename with a hyphen" "$(doc 'stand down, cross-staff')"

say "One full stop or one exclamation mark after the codename (dictation adds them)."
reseat Sextant
fires "one full stop" "$(doc 'Stand down, Sextant.')"
reseat Astrolabe
fires "one exclamation mark" "$(doc 'Stand down, Astrolabe!')"
reseat Compass
fires "capitals and an exclamation mark" "$(doc 'STAND DOWN, COMPASS!')"
reseat Quadrant
fires "a full stop, then a space and line breaks" "$(doc 'Stand down, Quadrant. \r\n\n')"
reseat Octant
fires "line breaks, the phrase, an exclamation mark, a tab" "$(doc '\n\nstand down, octant!\t')"

say "Carriage returns in what the hook reads."
probe_check
reseat Sextant
crlf_doc=$(printf '%s\r\n.' "$(doc 'Stand down, Sextant')")
fires "the document ends with CR LF" "${crlf_doc%.}"
reseat Astrolabe
crlf_doc=$(printf '{\r\n  "session_id": "abc123",\r\n  "hook_event_name": "UserPromptSubmit",\r\n  "prompt": "Stand down, Astrolabe"\r\n}\r\n.')
fires "a pretty-printed document with CRLF line endings" "${crlf_doc%.}"
reseat Compass
to_crlf "$seat"
check "seat.json now has CRLF on every line" all_crlf "$seat"
silent "CRLF seat.json, an ordinary prompt" "$(doc 'please carry on')"
silent "CRLF seat.json, the phrase for another codename" "$(doc 'Stand down, Sextant')"
fires "CRLF seat.json, the phrase" "$(doc 'Stand down, Compass')"

say "Where the hook is run from."
reseat Quadrant
mkdir -p sub/deeper sub/.succession
cat > sub/.succession/seat.json <<'EOF'
{
  "status": "occupied",
  "ordinal": "009",
  "codename": "Stray",
  "tenure": "009-stray",
  "seated": "2026-01-01T00:00:00Z",
  "updated": "2026-01-01T00:00:00Z"
}
EOF
FIRE_DIR="$PROJ/sub/deeper"
silent "a .succession folder that is not at the repository root is not used" "$(doc 'Stand down, Stray')"
fires "from a folder two levels inside the repository" "$(doc 'Stand down, Quadrant')"
FIRE_DIR=
rm -rf sub

reseat Octant
git worktree add -q "$WORK/linked" > /dev/null 2>&1
FIRE_DIR="$WORK/linked"
silent "a linked work tree that has no .succession folder" "$(doc 'Stand down, Octant')"
FIRE_DIR="$WORK/no-such-folder"
silent "a project folder that does not exist" "$(doc 'Stand down, Octant')"
FIRE_DIR=

mkdir "$WORK/redirect" "$WORK/elsewhere"
git init -q "$WORK/redirect"
git -C "$WORK/redirect" config core.worktree "$PROJ"
FIRE_DIR="$WORK/redirect"
fires "a repository whose config names this project as its work tree (git decides)" "$(doc 'Stand down, Octant')"
FIRE_DIR=

reseat Sextant
fd_before=$(grep -c '"type":"stand_down"' "$log")
OUT=$(printf '%s' "$(doc 'Stand down, Sextant')" | GIT_DIR="$PROJ/.git" GIT_WORK_TREE="$PROJ" CLAUDE_PROJECT_DIR="$WORK/elsewhere" "$SH" "$SCRIPTS/stand-down.sh" 2>&1)
check "GIT_DIR and GIT_WORK_TREE set (git decides): recorded" [ "$(grep -c '"type":"stand_down"' "$log")" -eq $((fd_before + 1)) ]
check "and the text says what the owner sends to close" contains "$OUT" "sending /succession:close"

reseat Astrolabe
OUT=$(cd "$PLUGIN" && printf '%s' "$(doc 'Stand down, Astrolabe')" | CDPATH="$WORK" CLAUDE_PROJECT_DIR="$PROJ" "$SH" scripts/stand-down.sh 2>&1)
check "the hook started by a relative path, with CDPATH set: recorded" contains "$OUT" "is recorded in .succession/log.jsonl"

say "What the hook starts. Stand-ins on PATH record each external tool."
watch_spawns
mkdir "$WORK/empty-repo"
git init -q "$WORK/empty-repo"
normal=$(doc "$(awk 'BEGIN { for (i = 0; i < 10; i++) printf "Please look at the retry setting and tell me what it does. "; }')")
# counted <project folder> <json>: runs the hook with the stand-ins first
# on PATH. STARTED is the list of tools it started.
counted() {
  OUT=$(printf '%s' "$2" | PATH="$SPAWN_DIR:$PATH" CLAUDE_PROJECT_DIR="$1" "$SH" "$SCRIPTS/stand-down.sh" 2>&1)
  RC=$?
  STARTED=$(spawned)
}
# other_than_awk <list>: the list with awk taken out.
other_than_awk() {
  oa_list=
  for oa_tool in $1; do
    [ "$oa_tool" = awk ] || oa_list="$oa_list$oa_tool "
  done
  printf '%s' "$oa_list"
}
PATH="$SPAWN_DIR:$PATH" "$SH" -c 'git --version' > /dev/null 2>&1
check "the stand-ins see a process being started" [ "$(spawned)" = git ]
reseat Astrolabe
: > "$SPAWN_LOG"
counted "$WORK/elsewhere" "$normal"
check "no repository: nothing started, no output (started: ${STARTED:-nothing})" [ "$RC$OUT$STARTED" = "0" ]
counted "$WORK/empty-repo" "$normal"
check "a repository without .succession: nothing started, no output (started: ${STARTED:-nothing})" [ "$RC$OUT$STARTED" = "0" ]
counted "$PROJ" "$normal"
check "seat held, an ordinary prompt of ${#normal} bytes: nothing started except awk (started: ${STARTED:-nothing})" [ "$RC$OUT$(other_than_awk "$STARTED")" = "0" ]
counted "$PROJ" "$(doc 'Stand down, Astrolabe')"
check "seat held, the phrase: git is asked before anything is written" contains " $STARTED " " git "
check "seat held, the phrase: recorded" contains "$OUT" "sending /succession:close"
quiet "$SH" "$SCRIPTS/log-append.sh" vacate "test: no handoff"
check "vacate: the entry's time is printed under its hash, and is the ts in the log" entry_time_ok "$OUT" "$log"
: > "$SPAWN_LOG"
counted "$PROJ" "$(doc 'Stand down, Astrolabe')"
check "seat vacant, the phrase: nothing started, no output (started: ${STARTED:-nothing})" [ "$RC$OUT$STARTED" = "0" ]
quiet "$SH" "$SCRIPTS/log-append.sh" seat Cross-staff

say "With nobody in the seat the phrase does nothing."
quiet "$SH" "$SCRIPTS/log-append.sh" vacate "test: no handoff"
silent "the phrase for the last officeholder, seat vacant" "$(doc 'Stand down, Cross-staff')"

say "Outside a Succession project the hook is silent."
mkdir "$WORK/plain"
OUT=$(printf '%s' "$(doc 'Stand down, Sextant')" | CLAUDE_PROJECT_DIR="$WORK/plain" "$SH" "$SCRIPTS/stand-down.sh" 2>&1)
RC=$?
check "no git repository: exit 0, no output" [ "$RC$OUT" = "0" ]

finish
