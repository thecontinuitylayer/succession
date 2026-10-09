#!/bin/sh
# Three tenures on a throwaway git project.
#
#   001 Sextant    works, checkpoints, closes with an honest handoff.
#   002 Astrolabe  verifies 001, works, closes with a handoff that holds
#                  one false file claim and one false commit claim.
#   003 Compass    verifies 002: the script reports both false claims,
#                  exits non-zero, and the owner seats Compass anyway.
#
# Then one line of log.jsonl is edited by hand and verify.sh names the
# broken entry, and the whole state is cloned with core.autocrlf=true to
# show that line endings do not change a verdict.
#
# This script plays the part the skills give to the model: it writes the
# handoff files and calls the same scripts the skills call.

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

title "Three tenures"
new_project three-tenures

mkdir src x
printf 'do not delete\n' > x/keep.txt
printf '# Throwaway project\n' > README.md
commit_all "Initial commit" > /dev/null

# ------------------------------------------------------------ tenure 001

say "Tenure 001. The seat skill runs the verifier before anything else."
run "verify.sh" "$SH" "$SCRIPTS/verify.sh"
check "nothing to verify yet, exit 0" [ "$RC" -eq 0 ]
verdict "001 arrival: $(last_line "$OUT") rc=$RC"

mkdir -p .succession
cp "$PLUGIN/skills/_shared/charter-template.md" .succession/charter.md

run "log-append.sh seat Sextant" "$SH" "$SCRIPTS/log-append.sh" seat Sextant
check "Sextant-001 holds the seat" contains "$OUT" "Seated: Sextant-001"
check "tenure folder 001-sextant exists" [ -d .succession/tenures/001-sextant ]

printf 'greeting=hello\n' > src/app.txt
c1=$(commit_all "Add the app")

run "log-append.sh checkpoint \"Added the app\"" "$SH" "$SCRIPTS/log-append.sh" checkpoint "Added the app"
h1=$(entry_hash "$OUT")
check "checkpoint entry hash is 64 hex digits" [ "${#h1}" -eq 64 ]
cat >> .succession/tenures/001-sextant/checkpoints.md <<EOF

## Added the app

Log entry: $h1

- CLAIM [commit:$c1] Added src/app.txt with the greeting
- CLAIM [file:src/app.txt@$c1] The app's settings file
EOF

printf 'retries=3\n' > src/util.txt
c2=$(commit_all "Add the retry setting")

cat > .succession/tenures/001-sextant/handoff.md <<EOF
# Handoff from Sextant-001

## Where things stand

The app has a greeting and a retry setting. Both are committed.

## Claims

- CLAIM [commit:$c1] Added the app with its greeting
- CLAIM [file:src/app.txt@$c1] The greeting lives in src/app.txt
- CLAIM [file:src/util.txt@$c2] The retry setting lives in src/util.txt
- CLAIM [log:$h1] Checkpoint recorded after the app was added
- CLAIM [none] The owner asked for three retries; ask them to confirm

## Open items

Nothing is deployed yet.

## Where to start

Make the greeting configurable.
EOF
printf 'Commit small. The owner likes one change per commit.\n' > .succession/tenures/001-sextant/lessons.md

run "verify.sh --draft   (the close skill checks its own draft)" "$SH" "$SCRIPTS/verify.sh" --draft
check "draft verdict: 5 claims, 4 pointers verified, 0 failed, 1 not checkable" contains "$OUT" "5 claims, 4 pointers verified, 0 failed, 1 not checkable."
check "a draft check records nothing" [ ! -e .succession/tenures/001-sextant/verification.md ]

run "log-append.sh close \"Built the app and its retry setting\" \"Mind the retries.\"" \
  "$SH" "$SCRIPTS/log-append.sh" close "Built the app and its retry setting" "Mind the retries."
check "001 closed, seat vacant" contains "$OUT" "The seat is vacant"
check "close: the entry's time is printed under its hash, and is the ts in the log" entry_time_ok "$OUT" .succession/log.jsonl
commit_all "Tenure 001 closes" > /dev/null

# ------------------------------------------------------------ tenure 002

say "Tenure 002. The seat cannot be claimed until the handoff has been verified."
run "log-append.sh seat Astrolabe   (too early)" "$SH" "$SCRIPTS/log-append.sh" seat Astrolabe
check "seat refused before verification (exit 6)" [ "$RC" -eq 6 ]

run "verify.sh" "$SH" "$SCRIPTS/verify.sh"
check "001's handoff: 5 claims, 4 pointers verified, 0 failed, 1 not checkable" contains "$(last_line "$OUT")" "5 claims, 4 pointers verified, 0 failed, 1 not checkable."
check "exit 0 when nothing failed" [ "$RC" -eq 0 ]
check "verification.md written next to the handoff" [ -s .succession/tenures/001-sextant/verification.md ]
check "verify.sh prints the hash of its log entry and no entry time" [ "$(printf '%s\n' "$OUT" | grep -c 'Log entry: ')$(printf '%s\n' "$OUT" | grep -c 'Entry time')" = "10" ]
verdict "002 arrival: $(last_line "$OUT") rc=$RC"

run "log-append.sh seat Astrolabe" "$SH" "$SCRIPTS/log-append.sh" seat Astrolabe
check "Astrolabe-002 holds the seat" contains "$OUT" "Seated: Astrolabe-002"

printf 'greeting=good morning\n' > src/app.txt
printf 'colour=blue\n' > src/config.txt
c3=$(commit_all "Change the greeting, add config")

run "log-append.sh checkpoint \"Changed the greeting\"" "$SH" "$SCRIPTS/log-append.sh" checkpoint "Changed the greeting"
h2=$(entry_hash "$OUT")

say "Astrolabe's handoff holds two false claims: a file that never existed and a commit that never happened."
cat > .succession/tenures/002-astrolabe/handoff.md <<EOF
# Handoff from Astrolabe-002

## Where things stand

The greeting changed, there is a config file, and the deploy script is in.

## Claims

- CLAIM [commit:$c3] Changed the greeting and added the config file
- CLAIM [file:src/app.txt@$c1] The original greeting from tenure 001
- CLAIM [file:src/config.txt@$c3] The config file
- CLAIM [log:$h2] Checkpoint recorded after the greeting changed
- CLAIM [file:src/deploy.txt@$c3] Added the deploy script
- CLAIM [commit:$FAKE_SHA] Fixed the flaky test
- CLAIM [cmd:rm -rf x] Cleaned the build folder
- CLAIM [file:../outside.txt@$c3] Notes kept next to the repository
- CLAIM [none] Told the owner about the staging deploy

## Where to start

Run the deploy script.
EOF
printf 'Nothing to add.\n' > .succession/tenures/002-astrolabe/lessons.md

run "log-append.sh close \"Changed the greeting and added config\" \"All done, all tested.\"" \
  "$SH" "$SCRIPTS/log-append.sh" close "Changed the greeting and added config" "All done, all tested."
check "002 closed, seat vacant" contains "$OUT" "The seat is vacant"
commit_all "Tenure 002 closes" > /dev/null

# ------------------------------------------------------------ tenure 003

say "Tenure 003. The successor's script checks every claim before the seat is taken."
run "verify.sh" "$SH" "$SCRIPTS/verify.sh"
check "verdict line: 9 claims, 4 pointers verified, 2 failed, 3 not checkable" [ "$(last_line "$OUT")" = "9 claims, 4 pointers verified, 2 failed, 3 not checkable." ]
check "exit is non-zero" [ "$RC" -ne 0 ]
check "the false file claim is reported FAILED" contains "$OUT" "[FAILED] file:src/deploy.txt@$c3"
check "the false commit claim is reported FAILED" contains "$OUT" "[FAILED] commit:$FAKE_SHA"
check "a file edited after its claimed commit is 'pointer verified, changed since'" contains "$OUT" "[pointer verified, changed since] file:src/app.txt@$c1"
check "cmd:rm -rf x is 'not checkable'" contains "$OUT" "[not checkable] cmd:rm -rf x"
check "a path with ../ is 'not checkable'" contains "$OUT" "[not checkable] file:../outside.txt@$c3"
check "nothing was executed: x/keep.txt is still there" [ -f x/keep.txt ]
check "the verdict is written to verification.md" grep -q "^Verdict: 9 claims, 4 pointers verified, 2 failed, 3 not checkable\.$" .succession/tenures/002-astrolabe/verification.md
check "the verdict is recorded in the log" grep -q '"type":"verify","tenure":"002-astrolabe","data":"9 claims, 4 pointers verified, 2 failed, 3 not checkable\.' .succession/log.jsonl
verdict "003 arrival: $(last_line "$OUT") rc=$RC"

say "A failed claim does not block the owner. It is shown, and it is on the record."
run "log-append.sh seat Compass" "$SH" "$SCRIPTS/log-append.sh" seat Compass
check "Compass-003 holds the seat" contains "$OUT" "Seated: Compass-003"
check "the seat entry carries the verdict it was taken under" grep -q '"type":"seat","tenure":"003-compass","data":"Compass-003 seated. Predecessor 002-astrolabe: 9 claims, 4 pointers verified, 2 failed' .succession/log.jsonl

printf '#!/bin/sh\necho deploying\n' > src/deploy.txt
c4=$(commit_all "Add the deploy script for real")
run "log-append.sh checkpoint \"Added the deploy script\"" "$SH" "$SCRIPTS/log-append.sh" checkpoint "Added the deploy script"
h3=$(entry_hash "$OUT")
cat > .succession/tenures/003-compass/handoff.md <<EOF
# Handoff from Compass-003

## Claims

- CLAIM [commit:$c4] Added the deploy script that tenure 002 said was there
- CLAIM [file:src/deploy.txt@$c4] The deploy script
- CLAIM [log:$h3] Checkpoint recorded after the deploy script went in
EOF
printf 'Check the handoff before you trust it.\n' > .succession/tenures/003-compass/lessons.md
run "log-append.sh close \"Added the missing deploy script\" \"Trust, then verify.\"" \
  "$SH" "$SCRIPTS/log-append.sh" close "Added the missing deploy script" "Trust, then verify."
commit_all "Tenure 003 closes" > /dev/null

run "verify.sh   (003's own handoff, as a fourth officeholder would see it)" "$SH" "$SCRIPTS/verify.sh"
check "003's handoff: 3 claims, 3 pointers verified, 0 failed, 0 not checkable" [ "$(last_line "$OUT")" = "3 claims, 3 pointers verified, 0 failed, 0 not checkable." ]
check "exit 0" [ "$RC" -eq 0 ]
verdict "after 003: $(last_line "$OUT") rc=$RC"

say "The lineage: three officeholders, numbers 001 to 003, none reused."
folders=
for d in .succession/tenures/*/; do
  d=${d%/}
  folders="$folders${d##*/} "
done
printf '      %s\n' "$folders"
check "three tenure folders" [ "$folders" = "001-sextant 002-astrolabe 003-compass " ]
check "three seated records" [ "$(grep -c '"event":"seated"' .succession/lineage.jsonl)" -eq 3 ]
check "three closed records" [ "$(grep -c '"event":"closed"' .succession/lineage.jsonl)" -eq 3 ]
check "seat.json reads vacant" grep -q '"status": "vacant"' .succession/seat.json

# ------------------------------------------------- a hand-edited log line

say "One line of log.jsonl is edited by hand."
line=$(grep -n '"type":"checkpoint","tenure":"001-sextant"' .succession/log.jsonl | cut -d: -f1)
seq=$(sed -n "${line}p" .succession/log.jsonl | sed 's/^{"seq":\([0-9]*\),.*/\1/')
printf '      editing line %s (entry %s): "Added the app" becomes "Added the app and all its tests"\n' "$line" "$seq"
sed "${line}s/Added the app/Added the app and all its tests/" .succession/log.jsonl > .succession/log.edited
cat .succession/log.edited > .succession/log.jsonl
rm -f .succession/log.edited

run "verify.sh" "$SH" "$SCRIPTS/verify.sh"
check "the chain is reported BROKEN" contains "$OUT" "Log chain: BROKEN"
check "the broken entry is named: entry $seq (line $line)" contains "$OUT" "BROKEN at entry $seq (line $line)"
check "exit is non-zero" [ "$RC" -ne 0 ]
verdict "edited log: $(last_line "$OUT") rc=$RC chain=$(printf '%s\n' "$OUT" | grep -c 'Log chain: BROKEN at entry')"

run "verify.sh --tenure 001-sextant   (its handoff cites the edited entry)" "$SH" "$SCRIPTS/verify.sh" --tenure 001-sextant
check "the log: claim on the edited entry is FAILED" contains "$OUT" "[FAILED] log:$h1"
verdict "edited log, 001: $(last_line "$OUT") rc=$RC"

sed "${line}s/Added the app and all its tests/Added the app/" .succession/log.jsonl > .succession/log.edited
cat .succession/log.edited > .succession/log.jsonl
rm -f .succession/log.edited
run "verify.sh   (after the edit is undone)" "$SH" "$SCRIPTS/verify.sh"
check "the chain is intact again" contains "$OUT" "Log chain: intact"
check "exit 0" [ "$RC" -eq 0 ]
quiet "$SH" "$SCRIPTS/verify.sh" --tenure 001-sextant
check "001's log: claim verifies again" contains "$OUT" "5 claims, 4 pointers verified, 0 failed, 1 not checkable."

# ------------------------------------------------ line endings: CRLF clone

say "The same state, cloned with core.autocrlf=true: every text file arrives with CRLF line endings."
commit_all "State after three tenures" > /dev/null
quiet "$SH" "$SCRIPTS/verify.sh" --tenure 002-astrolabe
want_line=$(last_line "$OUT")
want_rc=$RC

probe_check
git clone -q -c core.autocrlf=true "$PROJ" "$WORK/crlf-clone" 2> /dev/null
cd "$WORK/crlf-clone" || exit 99
git config user.name "Test Owner"
git config user.email "owner.invalid"
git config commit.gpgsign false
# The bytes on disk are counted. If a count is not what it should be, the
# way git sees each file is printed as well.
crlf_file() {
  printf '      %s: %s lines, %s carriage returns\n' "$1" "$(line_count "$1")" "$(cr_count "$1")"
  if all_crlf "$1"; then
    ok "the clone's $2 has CRLF on every line"
  else
    bad "the clone's $2 has CRLF on every line"
    git ls-files --eol -- "$1" | sed 's/^/      git ls-files --eol: /'
  fi
}
crlf_file .succession/log.jsonl log.jsonl
crlf_file .succession/lineage.jsonl lineage.jsonl
crlf_file .succession/seat.json seat.json
crlf_file .succession/tenures/002-astrolabe/handoff.md "handoff (002)"
crlf_file .succession/tenures/003-compass/verification.md "verification.md (003)"
check "the same files in the LF project hold no carriage return" \
  [ "$(cr_count "$PROJ/.succession/log.jsonl")$(cr_count "$PROJ/.succession/seat.json")$(cr_count "$PROJ/.succession/tenures/002-astrolabe/handoff.md")" = "000" ]

quiet env CLAUDE_PROJECT_DIR="$WORK/crlf-clone" "$SH" "$SCRIPTS/session-start.sh"
check "session-start reads the CRLF seat.json" contains "$OUT" "Seat: vacant. The last officeholder was Compass-003"
check "session-start reads the verdict from the CRLF log.jsonl" contains "$OUT" "as the log's last verify entry has it: 3 claims, 3 pointers verified, 0 failed, 0 not checkable."
check "session-start counts the CRLF lineage" contains "$OUT" "Lineage: 3 officeholders so far"

run "verify.sh --tenure 002-astrolabe   (in the CRLF clone)" "$SH" "$SCRIPTS/verify.sh" --tenure 002-astrolabe
check "same verdict line as in the LF project" [ "$(last_line "$OUT")" = "$want_line" ]
check "same exit code as in the LF project" [ "$RC" -eq "$want_rc" ]
check "the chain is intact with CRLF line endings" contains "$OUT" "Log chain: intact"
check "'changed since' is unaffected by line endings" contains "$OUT" "[pointer verified, changed since] file:src/app.txt@$c1"
verdict "crlf clone 002: $(last_line "$OUT") rc=$RC"

run "verify.sh   (in the CRLF clone)" "$SH" "$SCRIPTS/verify.sh"
check "003's handoff verifies in the CRLF clone" [ "$(last_line "$OUT")" = "3 claims, 3 pointers verified, 0 failed, 0 not checkable." ]
verdict "crlf clone 003: $(last_line "$OUT") rc=$RC"

run "log-append.sh seat Quadrant   (in the CRLF clone)" "$SH" "$SCRIPTS/log-append.sh" seat Quadrant
check "the next number is 004: CRLF state files are read correctly" contains "$OUT" "Seated: Quadrant-004"
quiet "$SH" "$SCRIPTS/log-append.sh" checkpoint "Mixed line endings in one log"
lf_lines=$(($(line_count .succession/log.jsonl) - $(cr_count .succession/log.jsonl)))
printf '      log.jsonl: %s lines end with CRLF, %s with LF\n' "$(cr_count .succession/log.jsonl)" "$lf_lines"
mixed=no
if [ "$(cr_count .succession/log.jsonl)" -gt 0 ] && [ "$lf_lines" -gt 0 ]; then
  mixed=yes
fi
check "log.jsonl now mixes CRLF entries with new LF entries" [ "$mixed" = yes ]
quiet "$SH" "$SCRIPTS/verify.sh" --draft --checkpoints
check "the chain stays intact when LF entries follow CRLF entries" contains "$OUT" "Log chain: intact"
to_crlf .succession/seat.json
OUT=$(printf '%s' '{"hook_event_name":"UserPromptSubmit","prompt":"Stand down, Quadrant"}' | CLAUDE_PROJECT_DIR="$WORK/crlf-clone" "$SH" "$SCRIPTS/stand-down.sh" 2>&1)
check "the stop phrase is recognised with a CRLF seat.json" contains "$OUT" "the stop phrase for Quadrant-004"
quiet "$SH" "$SCRIPTS/verify.sh" --draft --checkpoints
check "and the chain is still intact after the stand-down" contains "$OUT" "Log chain: intact"
verdict "crlf clone chain: $(printf '%s\n' "$OUT" | grep -c 'Log chain: intact') rc=$RC"

finish
