#!/bin/sh
# Hostile and malformed claims (verify.sh).
#
# A handoff is data. Whatever it says, verify.sh must run nothing named in
# it and open nothing outside the project. This test plants pointers that
# would do damage if they were ever executed or followed, then checks
# three things: each gets the right status, the tripwire files do not
# appear, and a pipe placed outside the project is never opened.

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

title "Hostile and malformed claims"
new_project claims

mkdir x docs
printf 'do not delete\n' > x/keep.txt
printf 'alpha\n' > a.txt
printf 'notes\n' > "docs/my notes.txt"
c1=$(commit_all "Initial commit")
short=$(printf '%s' "$c1" | cut -c1-7)
upper=$(printf '%s' "$c1" | tr 'abcdef' 'ABCDEF')

# A commit that exists but is not in the history of HEAD.
git checkout -q -b side
printf 'side\n' > side.txt
cside=$(commit_all "A commit on a side branch")
git checkout -q main

quiet "$SH" "$SCRIPTS/log-append.sh" seat Sextant
quiet "$SH" "$SCRIPTS/log-append.sh" checkpoint "A real checkpoint"
h1=$(entry_hash "$OUT")
hprefix=$(printf '%s' "$h1" | cut -c1-12)

# A named pipe outside the project. Opening it for reading blocks for
# ever, so if verify.sh returns at all it did not open it.
fifo="$WORK/outside.fifo"
have_fifo=0
if mkfifo "$fifo" 2> /dev/null; then
  have_fifo=1
fi

cat > .succession/tenures/001-sextant/handoff.md <<EOF
# Handoff from Sextant-001

## Claims that are true

- CLAIM [commit:$c1] full commit id
- CLAIM [commit:$short] seven-digit commit id
- CLAIM [commit:$upper] commit id in capitals
- CLAIM [file:a.txt@$c1] a file at the top of the repository
- CLAIM [file:./a.txt@$short] the same file written with ./
- CLAIM [file:docs/my notes.txt@$c1] a path with a space in it
- CLAIM [log:$h1] full log entry hash
- CLAIM [log:$hprefix] twelve-digit prefix of a log entry hash
  * CLAIM [commit:$c1] an indented claim with a star marker

## Claims that are false

- CLAIM [commit:$FAKE_SHA] a commit that does not exist
- CLAIM [commit:$cside] a commit that is not an ancestor of HEAD
- CLAIM [file:nope.txt@$c1] a file that is not in that commit
- CLAIM [file:a.txt@$FAKE_SHA] a real file at a commit that does not exist
- CLAIM [file:docs@$c1] a folder, not a file
- CLAIM [log:${FAKE_SHA}] a log entry that does not exist
- CLAIM [file:a.txt;touch pwned7@$c1] shell syntax in a path is just an odd file name: looked up, not run
- CLAIM [file:\$(touch pwned8)@$c1] command substitution in a path, likewise

## Claims a script cannot check

- CLAIM [cmd:rm -rf x] a command
- CLAIM [cmd:touch pwned1] another command
- CLAIM [sh:touch pwned2] a made-up pointer type
- CLAIM [url:https://example.invalid/proof] a link
- CLAIM [none] no pointer
- CLAIM [] an empty pointer
- CLAIM [commit:HEAD] a ref name, not a commit id
- CLAIM [commit:main] a branch name
- CLAIM [commit:abc] too short to be a commit id
- CLAIM [commit:] nothing after the colon
- CLAIM [commit:--help] an option in place of a commit id
- CLAIM [commit:\$(touch pwned3)] command substitution
- CLAIM [commit:\`touch pwned4\`] backticks
- CLAIM [commit:$c1; touch pwned5] a second command after a real id
- CLAIM [commit:$c1 --output=pwned6] an option after a real id
- CLAIM [file:../outside.fifo@$c1] a path that climbs out of the project
- CLAIM [file:docs/../../outside.fifo@$c1] a path that climbs out from a subfolder
- CLAIM [file:..@$c1] just two dots
- CLAIM [file:$fifo@$c1] an absolute path
- CLAIM [file:/etc/passwd@$c1] a system file
- CLAIM [file:~/.ssh/id_rsa@$c1] a path under the home folder
- CLAIM [file:C:\\Users\\owner\\secret.txt@$c1] a Windows path
- CLAIM [file:a.txt] no commit given
- CLAIM [file:a.txt@] an empty commit
- CLAIM [file:@$c1] an empty path
- CLAIM [file:a.txt@HEAD] a ref name after the @
- CLAIM [log:zzzz] not a hash
- CLAIM [log:\$(touch pwned9)] command substitution in a log pointer
- CLAIM [commit:$c1 an unclosed pointer
EOF
printf 'none\n' > .succession/tenures/001-sextant/lessons.md
quiet "$SH" "$SCRIPTS/log-append.sh" close "Wrote a hostile handoff" "Sorry."

say "verify.sh runs under a watchdog: if it opened the pipe it would hang and be killed."
"$SH" "$SCRIPTS/verify.sh" > "$WORK/verify.out" 2>&1 &
vpid=$!
(
  sleep 60
  kill "$vpid" 2> /dev/null
) > /dev/null 2>&1 &
wpid=$!
wait "$vpid"
RC=$?
kill "$wpid" 2> /dev/null
OUT=$(cat "$WORK/verify.out")
printf '%s\n' "$OUT" | sed 's/^/      /'
printf '      (exit %s)\n' "$RC"

check "verify.sh returned (it was not killed by the watchdog)" [ "$RC" -lt 128 ]
check "verdict line: 46 claims, 9 pointers verified, 8 failed, 29 not checkable" [ "$(last_line "$OUT")" = "46 claims, 9 pointers verified, 8 failed, 29 not checkable." ]
check "exit 1 because claims failed" [ "$RC" -eq 1 ]
verdict "claims: $(last_line "$OUT") rc=$RC"

say "Each claim got the status it should."
expect() {
  if contains "$OUT" "[$1] $2"; then
    ok "$1: $2"
  else
    bad "$1: $2"
  fi
}
expect "pointer verified" "commit:$c1"
expect "pointer verified" "commit:$short"
expect "pointer verified" "commit:$upper"
expect "pointer verified" "file:a.txt@$c1"
expect "pointer verified" "file:./a.txt@$short"
expect "pointer verified" "file:docs/my notes.txt@$c1"
expect "pointer verified" "log:$h1"
expect "pointer verified" "log:$hprefix"
expect "FAILED" "commit:$FAKE_SHA"
expect "FAILED" "commit:$cside"
expect "FAILED" "file:nope.txt@$c1"
expect "FAILED" "file:a.txt@$FAKE_SHA"
expect "FAILED" "file:docs@$c1"
expect "FAILED" "log:$FAKE_SHA"
expect "FAILED" "file:a.txt;touch pwned7@$c1"
expect "FAILED" "file:\$(touch pwned8)@$c1"
expect "not checkable" "cmd:rm -rf x"
expect "not checkable" "cmd:touch pwned1"
expect "not checkable" "sh:touch pwned2"
expect "not checkable" "url:https://example.invalid/proof"
expect "not checkable" "none"
expect "not checkable" "(no pointer)"
expect "not checkable" "commit:HEAD"
expect "not checkable" "commit:main"
expect "not checkable" "commit:abc"
expect "not checkable" "commit:--help"
expect "not checkable" "commit:\$(touch pwned3)"
expect "not checkable" "commit:'touch pwned4'"
expect "not checkable" "commit:$c1; touch pwned5"
expect "not checkable" "commit:$c1 --output=pwned6"
expect "not checkable" "file:../outside.fifo@$c1"
expect "not checkable" "file:docs/../../outside.fifo@$c1"
expect "not checkable" "file:..@$c1"
expect "not checkable" "file:$fifo@$c1"
expect "not checkable" "file:/etc/passwd@$c1"
expect "not checkable" "file:~/.ssh/id_rsa@$c1"
expect "not checkable" "file:C:\\Users\\owner\\secret.txt@$c1"
expect "not checkable" "file:a.txt"
expect "not checkable" "file:a.txt@"
expect "not checkable" "file:@$c1"
expect "not checkable" "file:a.txt@HEAD"
expect "not checkable" "log:zzzz"
expect "not checkable" "log:\$(touch pwned9)"
expect "not checkable" "commit:$c1 an unclosed pointer"

say "Nothing named in a claim was executed."
check "x/keep.txt is still there (cmd:rm -rf x did not run)" [ -f x/keep.txt ]
tripped=
for f in pwned1 pwned2 pwned3 pwned4 pwned5 pwned6 pwned7 pwned8 pwned9; do
  if [ -e "$f" ] || [ -e "$WORK/$f" ]; then
    tripped="$tripped $f"
  fi
done
check "no tripwire file was created" [ -z "$tripped" ]
check "git status shows no new files besides .succession" [ -z "$(git status --porcelain | grep -v '\.succession/')" ]

say "Nothing outside the project was opened."
if [ "$have_fifo" -eq 1 ]; then
  ok "the pipe outside the project was never opened (verify.sh returned)"
else
  printf '  skip  named pipes are not available here\n'
fi

say "A handoff that is a symbolic link is refused, not followed."
quiet "$SH" "$SCRIPTS/log-append.sh" seat Astrolabe
if [ "$have_fifo" -eq 1 ]; then
  target=$fifo
else
  target=/etc/hostname
fi
ln -s "$target" .succession/tenures/002-astrolabe/handoff.md 2> /dev/null
if [ -L .succession/tenures/002-astrolabe/handoff.md ]; then
  "$SH" "$SCRIPTS/verify.sh" --draft > "$WORK/verify.out" 2>&1 &
  vpid=$!
  (
    sleep 60
    kill "$vpid" 2> /dev/null
  ) > /dev/null 2>&1 &
  wpid=$!
  wait "$vpid"
  RC=$?
  kill "$wpid" 2> /dev/null
  OUT=$(cat "$WORK/verify.out")
  printf '      %s\n      (exit %s)\n' "$OUT" "$RC"
  check "verify.sh refuses the link (exit 4)" [ "$RC" -eq 4 ]
  check "it says why" contains "$OUT" "refusing to use a symbolic link"
  quiet "$SH" "$SCRIPTS/log-append.sh" close "summary" "words"
  check "log-append.sh close refuses it too (exit 4)" [ "$RC" -eq 4 ]
  rm -f .succession/tenures/002-astrolabe/handoff.md
else
  printf '  skip  symbolic links are not available here\n'
fi

say "A handoff with Windows line endings gives the same statuses."
printf '# Handoff\r\n\r\n- CLAIM [commit:%s] real\r\n- CLAIM [file:a.txt@%s] real\r\n- CLAIM [commit:%s] false\r\n- CLAIM [cmd:rm -rf x] command\r\n' "$c1" "$c1" "$FAKE_SHA" > .succession/tenures/002-astrolabe/handoff.md
quiet "$SH" "$SCRIPTS/verify.sh" --draft
check "CRLF handoff: 4 claims, 2 pointers verified, 1 failed, 1 not checkable" [ "$(last_line "$OUT")" = "4 claims, 2 pointers verified, 1 failed, 1 not checkable." ]
verdict "claims crlf handoff: $(last_line "$OUT") rc=$RC"

say "A branch or a tag whose name looks like a commit id is not a commit id."
# claim-format.md says branch names and tags are not accepted. A name made
# of hex digits must not get round that.
git tag deadbeef1 "$c1"
git branch cafe1234 "$c1"
printf 'later\n' > later.txt
c9=$(commit_all "A later commit")
git tag "$short" "$c9" 2> /dev/null
printf '# Handoff\n\n- CLAIM [commit:deadbeef1] a tag named in hex digits\n- CLAIM [commit:cafe1234] a branch named in hex digits\n- CLAIM [file:a.txt@deadbeef1] a file at that tag\n- CLAIM [commit:%s] a real commit id, which a tag of the same name must not hide\n- CLAIM [file:later.txt@%s] a file that is in the tagged commit, not in the claimed one\n' "$short" "$short" > .succession/tenures/002-astrolabe/handoff.md
run "verify.sh --draft" "$SH" "$SCRIPTS/verify.sh" --draft
check "the tag name is not taken for a commit" contains "$OUT" "[FAILED] commit:deadbeef1"
check "the branch name is not taken for a commit" contains "$OUT" "[FAILED] commit:cafe1234"
check "nor is the tag name after @ in a file pointer" contains "$OUT" "[FAILED] file:a.txt@deadbeef1"
check "a real commit id still verifies when a tag carries the same name" contains "$OUT" "[pointer verified] commit:$short"
check "and it is the commit that is looked in, not the tag's" contains "$OUT" "[FAILED] file:later.txt@$short"
check "verdict line: 5 claims, 1 pointers verified, 4 failed, 0 not checkable" [ "$(last_line "$OUT")" = "5 claims, 1 pointers verified, 4 failed, 0 not checkable." ]
verdict "claims hex-named refs: $(last_line "$OUT") rc=$RC"
git tag -d deadbeef1 "$short" > /dev/null 2>&1
git branch -D cafe1234 > /dev/null 2>&1

say "Claim text cannot put HTML, an image or a link into verification.md."
quiet "$SH" "$SCRIPTS/log-append.sh" vacate "End of the draft tenure"
quiet "$SH" "$SCRIPTS/log-append.sh" seat Compass
ten=$(sed -n 's/.*"tenure": "\(.*\)".*/\1/p' .succession/seat.json)
printf '# Handoff\n\n- CLAIM [commit:%s] <img src=x onerror=alert(1)> ![pixel](https://tracker.example/p.png) [click](https://example.org) <script>x</script>\n' "$c1" > ".succession/tenures/$ten/handoff.md"
quiet "$SH" "$SCRIPTS/log-append.sh" close "A handoff with markup in it" "None."
quiet "$SH" "$SCRIPTS/verify.sh"
vmd=".succession/tenures/$ten/verification.md"
check "verification.md was written" [ -s "$vmd" ]
check "no HTML tag from the claim is in it" [ "$(grep -c '<img\|<script' "$vmd")" -eq 0 ]
check "no Markdown image or link from the claim is in it" [ "$(grep -c '!\[pixel\]\|\[click\](' "$vmd")" -eq 0 ]
check "the text is still there to read, escaped" grep -q '&lt;img src=x' "$vmd"

say "Outside a git repository the scripts say so and stop."
mkdir "$WORK/plain"
cd "$WORK/plain" || exit 99
quiet env GIT_CEILING_DIRECTORIES="$WORK" "$SH" "$SCRIPTS/verify.sh"
check "verify.sh: exit 3 and a plain message" [ "$RC" -eq 3 ]
check "the message names the problem" contains "$OUT" "Succession needs a git repository"
quiet env GIT_CEILING_DIRECTORIES="$WORK" "$SH" "$SCRIPTS/log-append.sh" seat Sextant
check "log-append.sh seat: exit 3" [ "$RC" -eq 3 ]
check "no .succession folder was created" [ ! -e .succession ]

finish
