#!/bin/sh
# Things the plugin must not do, and things it must notice.
#
#   - No write through a symbolic link. A cloned repository can carry
#     links under .succession/, at the paths of the short-lived files
#     too. None may be followed to a file outside .succession/.
#   - The handoff is bound to the log: a line added after the close shows.
#   - The seat gate asks the log, not lineage.jsonl, which tenure ended last.
#   - State files put back to an older version (git stash, git checkout,
#     git reset --hard) are noticed where the tenure folders show more.
#   - The charter is written by the script when there is none, and an
#     existing one is never changed by it.

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

title "Safety"
new_project safety
printf 'one\n' > a.txt
c1=$(commit_all "Initial commit")
OUTSIDE="$WORK/outside"
mkdir "$OUTSIDE"

# write_handoff <tenure>
write_handoff() {
  printf '# Handoff\n\n- CLAIM [commit:%s] The initial commit\n- CLAIM [none] A fact a script cannot check\n' "$c1" > ".succession/tenures/$1/handoff.md"
}

# Symbolic links may not exist here (Git Bash makes copies unless Windows
# is set up for links). The link cases are skipped then, and say so.
ln -s "$OUTSIDE" "$WORK/link-probe" 2> /dev/null
if [ -L "$WORK/link-probe" ]; then
  have_links=1
else
  have_links=0
  printf '  skip  symbolic links are not available here: the link cases are not run\n'
fi

# ------------------------------------------------------- the charter script

say "The charter is written by the script when there is none, and never changed by it."
run "log-append.sh charter" "$SH" "$SCRIPTS/log-append.sh" charter
check "exit 0" [ "$RC" -eq 0 ]
check "charter.md is the plugin's template, byte for byte" cmp -s .succession/charter.md "$PLUGIN/skills/_shared/charter-template.md"
check "no log entry is written for it" [ ! -e .succession/log.jsonl ]
printf 'The owner changed this charter.\n' > .succession/charter.md
quiet "$SH" "$SCRIPTS/log-append.sh" charter
check "a second call leaves the owner's charter alone" [ "$(cat .succession/charter.md)" = "The owner changed this charter." ]
check "and says so" contains "$OUT" "left as it is"
if [ "$have_links" -eq 1 ]; then
  rm -f .succession/charter.md
  printf 'precious\n' > "$OUTSIDE/charter-target.txt"
  ln -s "$OUTSIDE/charter-target.txt" .succession/charter.md
  quiet "$SH" "$SCRIPTS/log-append.sh" charter
  check "a charter.md that is a link is refused (exit 4)" [ "$RC" -eq 4 ]
  check "the file it points at is untouched" [ "$(cat "$OUTSIDE/charter-target.txt")" = "precious" ]
  rm -f .succession/charter.md
  ln -s "$OUTSIDE/charter-tmp.txt" .succession/charter.md.tmp
  quiet "$SH" "$SCRIPTS/log-append.sh" charter
  check "a link at charter.md.tmp is not followed: nothing appears outside" [ ! -e "$OUTSIDE/charter-tmp.txt" ]
  check "the charter is written, as a plain file" plain_file .succession/charter.md
fi
cp "$PLUGIN/skills/_shared/charter-template.md" .succession/charter.md

# ------------------------------------------------------------ links: seat

if [ "$have_links" -eq 1 ]; then
  say "A link at seat.json.tmp: the seat is written inside .succession, not through the link."
  ln -s "$OUTSIDE/seat-target" .succession/seat.json.tmp
  run "log-append.sh seat Sextant" "$SH" "$SCRIPTS/log-append.sh" seat Sextant
  check "exit 0" [ "$RC" -eq 0 ]
  check "nothing was created outside .succession" [ ! -e "$OUTSIDE/seat-target" ]
  check "seat.json is a plain file, not a link" plain_file .succession/seat.json
  check "the project is not stuck: seat.json reads occupied" grep -q '"status": "occupied"' .succession/seat.json
else
  quiet "$SH" "$SCRIPTS/log-append.sh" seat Sextant
fi
quiet "$SH" "$SCRIPTS/log-append.sh" checkpoint "Started"
write_handoff 001-sextant

if [ "$have_links" -eq 1 ]; then
  say "A link where the lock folder goes is refused, and nothing it points at is removed."
  mkdir "$OUTSIDE/lockdir"
  sh -c 'echo $$' > "$OUTSIDE/lockdir/pid"
  ln -s "$OUTSIDE/lockdir" .succession/.lock
  quiet "$SH" "$SCRIPTS/log-append.sh" checkpoint "Behind a linked lock"
  check "refused (exit 4)" [ "$RC" -eq 4 ]
  check "it says why" contains "$OUT" "refusing to use a symbolic link"
  check "the pid file in the folder the link points at is still there" [ -f "$OUTSIDE/lockdir/pid" ]
  rm -f .succession/.lock

  say "A link at the path of the stand-down note is not followed."
  ln -s "$OUTSIDE/stood-down-target" .succession/tenures/001-sextant/stood-down
  quiet "$SH" "$SCRIPTS/log-append.sh" stand_down
  check "the stand-down is recorded" [ "$RC" -eq 0 ]
  check "nothing was created outside .succession" [ ! -e "$OUTSIDE/stood-down-target" ]
  check "the note is a plain file" plain_file .succession/tenures/001-sextant/stood-down
else
  quiet "$SH" "$SCRIPTS/log-append.sh" stand_down
fi
check "a stand-down leaves a note in the tenure folder" grep -q '^The owner stood down Sextant-001 at ' .succession/tenures/001-sextant/stood-down

quiet "$SH" "$SCRIPTS/log-append.sh" close "First tenure" "Good luck."
check "001 closed" [ "$RC" -eq 0 ]

# ---------------------------------------------------------- links: verify

if [ "$have_links" -eq 1 ]; then
  say "A link at verification.md.tmp: the file it points at is not overwritten."
  printf 'precious\n' > "$OUTSIDE/precious.txt"
  ln -s "$OUTSIDE/precious.txt" .succession/tenures/001-sextant/verification.md.tmp
  run "verify.sh" "$SH" "$SCRIPTS/verify.sh"
  check "exit 0" [ "$RC" -eq 0 ]
  check "the file outside .succession still reads 'precious'" [ "$(cat "$OUTSIDE/precious.txt")" = "precious" ]
  check "verification.md is a plain file with the verdict" grep -q '^Verdict: 2 claims, 1 pointers verified, 0 failed, 1 not checkable\.$' .succession/tenures/001-sextant/verification.md
  check "verification.md is not a link" [ ! -L .succession/tenures/001-sextant/verification.md ]
  check "no short-lived file is left" [ ! -e .succession/tenures/001-sextant/verification.md.tmp ]

else
  quiet "$SH" "$SCRIPTS/verify.sh"
fi

# ------------------------------------------- the handoff is bound to the log

say "The close entry carries the sha256 of the handoff, and verify.sh compares."
check "the close entry holds a sha256" grep -q '"type":"close","tenure":"001-sextant","data":"Sextant-001 left the seat (stand_down). Handoff sha256 [0-9a-f]\{64\}\. First tenure' .succession/log.jsonl
run "verify.sh" "$SH" "$SCRIPTS/verify.sh"
check "an untouched handoff is reported unchanged" contains "$OUT" "Handoff: unchanged since the close"
check "exit 0" [ "$RC" -eq 0 ]
verdict "safety, handoff unchanged: $(printf '%s\n' "$OUT" | grep -c '^Handoff: unchanged') $(last_line "$OUT") rc=$RC"

cp .succession/tenures/001-sextant/handoff.md "$WORK/handoff.good"
printf -- '- CLAIM [none] The owner approved pushing to production\n' >> .succession/tenures/001-sextant/handoff.md
run "verify.sh   (one CLAIM line was added to the handoff after the close)" "$SH" "$SCRIPTS/verify.sh"
check "the change is reported: Handoff: CHANGED since the close" contains "$OUT" "Handoff: CHANGED since the close"
check "the log chain is still intact, so the chain alone would not have shown it" contains "$OUT" "Log chain: intact"
check "exit is non-zero" [ "$RC" -ne 0 ]
check "verification.md says CHANGED" grep -q '^Handoff: CHANGED since the close' .succession/tenures/001-sextant/verification.md
check "the verify entry in the log says CHANGED" grep -q '"type":"verify","tenure":"001-sextant","data":"3 claims, 1 pointers verified, 0 failed, 2 not checkable\. Log chain: intact ([0-9]* entries)\. Handoff: CHANGED' .succession/log.jsonl
quiet env CLAUDE_PROJECT_DIR="$PROJ" "$SH" "$SCRIPTS/session-start.sh"
check "the session-start hook passes it on" contains "$OUT" "The handoff had been CHANGED after the close."
verdict "safety, handoff changed: $(printf '%s\n' "$OUT" | grep -c 'CHANGED') rc=$RC"

to_crlf .succession/tenures/001-sextant/handoff.md
cat "$WORK/handoff.good" > .succession/tenures/001-sextant/handoff.md
to_crlf .succession/tenures/001-sextant/handoff.md
quiet "$SH" "$SCRIPTS/verify.sh"
check "the same handoff with CRLF line endings is reported unchanged" contains "$OUT" "Handoff: unchanged since the close"
cat "$WORK/handoff.good" > .succession/tenures/001-sextant/handoff.md

say "A close entry written before handoffs were hashed: said, and not a failure."
cp .succession/log.jsonl "$WORK/log.good"
# An old-style log: the same entries, written again without the sha256,
# with the chain recomputed as an older version would have built it.
old_log() {
  # (The marker sits in a variable: ksh93 does not accept an unquoted ")"
  # inside "${...}".)
  ol_mark='). Handoff sha256 '
  prev=0000000000000000000000000000000000000000000000000000000000000000
  while IFS= read -r ol_line; do
    ol_body=${ol_line%,\"prev\":\"*}
    case $ol_body in
      *"$ol_mark"*)
        ol_head=${ol_body%%"$ol_mark"*}
        ol_tail=${ol_body#*"$ol_mark"}
        ol_body="$ol_head). ${ol_tail#*. }"
        ;;
    esac
    ol_body="$ol_body,\"prev\":\"$prev\""
    if command -v sha256sum > /dev/null 2>&1; then
      prev=$(printf '%s}' "$ol_body" | sha256sum)
    else
      prev=$(printf '%s}' "$ol_body" | shasum -a 256)
    fi
    prev=${prev%% *}
    printf '%s,"hash":"%s"}\n' "$ol_body" "$prev"
  done < "$1"
}
old_log "$WORK/log.good" > .succession/log.jsonl
quiet "$SH" "$SCRIPTS/verify.sh" --tenure 001-sextant
printf '%s\n' "$OUT" | grep '^Handoff:' | sed 's/^/      /'
check "the chain of the old-style log is intact" contains "$OUT" "Log chain: intact"
check "it says no sha256 was recorded" contains "$OUT" "Handoff: no sha256 of it was recorded at the close"
check "that is not a failure: exit 0" [ "$RC" -eq 0 ]
cat "$WORK/log.good" > .succession/log.jsonl

# --------------------------------------- the seat gate asks the log, not the lineage

say "A line taken out of lineage.jsonl does not move the seat gate."
quiet "$SH" "$SCRIPTS/verify.sh"
quiet "$SH" "$SCRIPTS/log-append.sh" seat Astrolabe
check "Astrolabe is seated" contains "$OUT" "Seated: Astrolabe-"
ten2=$(sed -n 's/.*"tenure": "\(.*\)".*/\1/p' .succession/seat.json)
printf '# Handoff\n\n- CLAIM [commit:%s] A commit that never happened\n' "$FAKE_SHA" > ".succession/tenures/$ten2/handoff.md"
quiet "$SH" "$SCRIPTS/log-append.sh" close "Second tenure" "All done."
cp .succession/lineage.jsonl "$WORK/lineage.good"
sed '$d' "$WORK/lineage.good" > .succession/lineage.jsonl
printf '      the closing line of %s is removed from lineage.jsonl\n' "$ten2"
run "log-append.sh seat Compass   (the handoff of $ten2 has not been verified)" "$SH" "$SCRIPTS/log-append.sh" seat Compass
check "the seat is refused (exit 6): the log still says $ten2 ended last" [ "$RC" -eq 6 ]
run "verify.sh" "$SH" "$SCRIPTS/verify.sh"
check "verify.sh checks the handoff of $ten2, not an older one" contains "$OUT" "Succession verify: handoff of $ten2"
check "and reports its false claim" [ "$(last_line "$OUT")" = "1 claims, 0 pointers verified, 1 failed, 0 not checkable." ]
verdict "safety, lineage cut: $(last_line "$OUT") rc=$RC"
cat "$WORK/lineage.good" > .succession/lineage.jsonl

# ------------------------------------------------ state put back by git

say "State files put back to an older version: the next seating says so."
commit_all "The record so far, committed as the README advises" > /dev/null
quiet "$SH" "$SCRIPTS/log-append.sh" seat Compass
check "Compass is seated" contains "$OUT" "Seated: Compass-"
check "no warning when nothing is behind" lacks "$OUT" "WARNING"
ten3=$(sed -n 's/.*"tenure": "\(.*\)".*/\1/p' .succession/seat.json)
quiet "$SH" "$SCRIPTS/log-append.sh" stand_down
check "Compass is stood down" grep -q '"status": "stood_down"' .succession/seat.json
git stash > /dev/null 2>&1
printf '      git stash: seat.json, log.jsonl and lineage.jsonl are back at the last commit\n'
check "seat.json reads vacant again, as if Compass had never been seated" grep -q '"status": "vacant"' .succession/seat.json
check "the folder of the vanished tenure is still there" [ -d ".succession/tenures/$ten3" ]
quiet env CLAUDE_PROJECT_DIR="$PROJ" "$SH" "$SCRIPTS/session-start.sh"
printf '%s\n' "$OUT" | sed -n '2p' | cut -c 1-200 | sed 's/^/      /'
check "the session-start hook warns, and names the folder" contains "$OUT" "WARNING: the folder .succession/tenures/$ten3 exists, but seat.json does not show that tenure"
check "it names the git commands that do this" contains "$OUT" "git stash, git checkout, git reset --hard"
run "log-append.sh seat Quadrant" "$SH" "$SCRIPTS/log-append.sh" seat Quadrant
check "the seat is not blocked" contains "$OUT" "Seated: Quadrant-"
check "the number of the vanished tenure is not reused" [ "$(sed -n 's/.*"tenure": "\(.*\)".*/\1/p' .succession/seat.json | cut -c 1-3)" != "$(printf '%s' "$ten3" | cut -c 1-3)" ]
check "the seating warns, and names the folder" contains "$OUT" "WARNING: the folder .succession/tenures/$ten3 is there, but seat.json and the log do not show that tenure"
verdict "safety, state put back: $(printf '%s\n' "$OUT" | grep -c '^WARNING')"

say "A stand-down that git took back: the note in the tenure folder still says it."
ten4=$(sed -n 's/.*"tenure": "\(.*\)".*/\1/p' .succession/seat.json)
commit_all "Quadrant seated, committed" > /dev/null
quiet "$SH" "$SCRIPTS/log-append.sh" stand_down
git checkout -- . > /dev/null 2>&1
printf '      git checkout -- . : seat.json reads occupied again and the log has lost the stand_down entry\n'
check "seat.json reads occupied" grep -q '"status": "occupied"' .succession/seat.json
check "the log holds no stand_down entry for this tenure" [ "$(grep -c "\"type\":\"stand_down\",\"tenure\":\"$ten4\"" .succession/log.jsonl)" -eq 0 ]
quiet env CLAUDE_PROJECT_DIR="$PROJ" "$SH" "$SCRIPTS/session-start.sh"
check "the hook says the stand-down is in force" contains "$OUT" "treats the stand-down as in force"
check "it does not present the seat as simply occupied" lacks "$OUT" "Seat: occupied by"
OUT=$(printf '%s' '{"hook_event_name":"UserPromptSubmit","prompt":"Stand down, Quadrant"}' | CLAUDE_PROJECT_DIR="$PROJ" "$SH" "$SCRIPTS/stand-down.sh" 2>&1)
check "the stop phrase records it again" grep -q "\"type\":\"stand_down\",\"tenure\":\"$ten4\"" .succession/log.jsonl
quiet env CLAUDE_PROJECT_DIR="$PROJ" "$SH" "$SCRIPTS/session-start.sh"
check "after that the hook reads stood down, without a warning" contains "$OUT" "was stood down by the owner"

say "The log put back on its own: seat.json and the log disagree, and that is said."
write_handoff "$ten4"
quiet "$SH" "$SCRIPTS/log-append.sh" close "Fourth tenure" "None."
quiet "$SH" "$SCRIPTS/verify.sh"
quiet env CLAUDE_PROJECT_DIR="$PROJ" "$SH" "$SCRIPTS/session-start.sh"
check "no warning while seat.json and the log agree" lacks "$OUT" "WARNING"
git checkout -- .succession/log.jsonl > /dev/null 2>&1
printf '      git checkout -- .succession/log.jsonl : the log ends with the seating of %s again; seat.json reads vacant\n' "$ten4"
quiet env CLAUDE_PROJECT_DIR="$PROJ" "$SH" "$SCRIPTS/session-start.sh"
printf '%s\n' "$OUT" | sed -n '2p' | cut -c 1-200 | sed 's/^/      /'
check "the session-start hook says the two disagree" contains "$OUT" "WARNING: seat.json reads vacant for $ten4, but the last entry in log.jsonl that changed the seat is \"seat\" for $ten4."
run "log-append.sh seat Backstaff" "$SH" "$SCRIPTS/log-append.sh" seat Backstaff
check "the seat is not blocked" contains "$OUT" "Seated: Backstaff-"
check "the seating says the two disagreed" contains "$OUT" "WARNING: before this seating, seat.json and the log disagreed: seat.json reads vacant for $ten4, and the last entry in log.jsonl that changed the seat is \"seat\" for $ten4."
verdict "safety, log put back: $(printf '%s\n' "$OUT" | grep -c '^WARNING')"
quiet env CLAUDE_PROJECT_DIR="$PROJ" "$SH" "$SCRIPTS/session-start.sh"
check "after the seating the two agree again: no warning" lacks "$OUT" "WARNING"

say "seat.json put back on its own after a stand-down: the log still says it."
ten5=$(sed -n 's/.*"tenure": "\(.*\)".*/\1/p' .succession/seat.json)
cp .succession/seat.json "$WORK/seat.occupied"
quiet "$SH" "$SCRIPTS/log-append.sh" stand_down
cat "$WORK/seat.occupied" > .succession/seat.json
rm -f ".succession/tenures/$ten5/stood-down"
quiet env CLAUDE_PROJECT_DIR="$PROJ" "$SH" "$SCRIPTS/session-start.sh"
check "the hook says the stand-down is in force, on the log's word" contains "$OUT" "Seat: WARNING. The log says the owner stood Backstaff-"
check "it does not present the seat as simply occupied" lacks "$OUT" "Seat: occupied by"
OUT=$(printf '%s' '{"hook_event_name":"UserPromptSubmit","prompt":"Stand down, Backstaff"}' | CLAUDE_PROJECT_DIR="$PROJ" "$SH" "$SCRIPTS/stand-down.sh" 2>&1)
check "the stop phrase puts seat.json right again" grep -q '"status": "stood_down"' .succession/seat.json

if [ "$have_links" -eq 1 ]; then
  say "A tenure folder planted as a link for the next officeholder is not used."
  quiet "$SH" "$SCRIPTS/log-append.sh" vacate "End of the tenure before the link cases"
  mkdir "$OUTSIDE/planted"
  ln -s "$OUTSIDE/planted" .succession/tenures/008-octant
  quiet "$SH" "$SCRIPTS/log-append.sh" seat Octant
  printf '%s\n' "$OUT" | sed -n '1p' | sed 's/^/      /'
  check "nothing was written into the folder the link points at" [ -z "$(ls -A "$OUTSIDE/planted")" ]
  check "the officeholder was not seated in a linked folder" [ ! -e "$OUTSIDE/planted/checkpoints.md" ]
  rm -f .succession/tenures/008-octant
  case $(sed -n 's/.*"status": "\(.*\)".*/\1/p' .succession/seat.json) in
    occupied) quiet "$SH" "$SCRIPTS/log-append.sh" vacate "Seated during the link test" ;;
  esac

  say "A tenures folder that is a link is refused."
  mv .succession/tenures "$OUTSIDE/tenures-moved"
  ln -s "$OUTSIDE/tenures-moved" .succession/tenures
  quiet "$SH" "$SCRIPTS/verify.sh"
  check "verify.sh refuses (exit 4)" [ "$RC" -eq 4 ]
  quiet "$SH" "$SCRIPTS/log-append.sh" seat Alidade
  check "log-append.sh seat refuses (exit 4)" [ "$RC" -eq 4 ]
  rm -f .succession/tenures
  mv "$OUTSIDE/tenures-moved" .succession/tenures
fi

finish
