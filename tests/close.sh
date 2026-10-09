#!/bin/sh
# The ending of a close.
#
# log-append.sh close ends with one line that starts with "Git:". It tells
# the owner whether the files under .succession/ are waiting to be
# committed and gives the one command line that commits them. The script
# itself stages nothing and commits nothing.
#
# Covers: the exact text of that line, that the close leaves git's index
# and history alone, that the printed command line does what the line
# says when the owner runs it (and takes nothing else into the commit),
# and the two cases where there is nothing to commit by that command or
# where git's own settings would hide the files.

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

title "The ending of a close"
new_project close
printf 'one\n' > a.txt
c1=$(commit_all "Initial commit")

# write_handoff <tenure> <Name-NNN>
write_handoff() {
  cat > ".succession/tenures/$1/handoff.md" <<EOF
# Handoff from $2

Written: pending

## Claims

- CLAIM [commit:$c1] The initial commit
- CLAIM [none] A fact a script cannot check
EOF
  printf 'Nothing to add.\n' > ".succession/tenures/$1/lessons.md"
}

# git_lines <output>: how many lines of it start with "Git:".
git_lines() {
  printf '%s\n' "$1" | grep -c '^Git:'
}

want_cmd='git add .succession; git commit -m "Succession: Sextant-001 closed" -- .succession'
want_line="Git: the state files in .succession/ are not committed yet. To commit them: $want_cmd"

say "A close ends with one line about git, and the script commits nothing."
quiet "$SH" "$SCRIPTS/log-append.sh" seat Sextant
check "seat prints no Git line" [ "$(git_lines "$OUT")" -eq 0 ]
quiet "$SH" "$SCRIPTS/log-append.sh" checkpoint "Started"
check "checkpoint prints no Git line" [ "$(git_lines "$OUT")" -eq 0 ]
write_handoff 001-sextant Sextant-001

# Something of the owner's own is staged, and something else is edited
# and not staged. Neither may end up in the commit of .succession/.
printf 'staged by the owner\n' > staged.txt
git add staged.txt
printf 'two\n' >> a.txt

run "log-append.sh close \"First tenure\" \"Good luck.\"" "$SH" "$SCRIPTS/log-append.sh" close "First tenure" "Good luck."
check "exit 0" [ "$RC" -eq 0 ]
check "line 1 says the tenure is closed and the seat is vacant" \
  [ "$(printf '%s\n' "$OUT" | sed -n '1p')" = "Tenure closed: Sextant-001. The seat is vacant." ]
check "the entry's time is printed under its hash" entry_time_ok "$OUT" .succession/log.jsonl
check "a line says where the handoff is" \
  [ "$(printf '%s\n' "$OUT" | grep -c '^Handoff: \.succession/tenures/001-sextant/handoff\.md$')" -eq 1 ]
check "one line starts with Git:, and it is the last line" \
  [ "$(git_lines "$OUT")$(last_line "$OUT" | grep -c '^Git:')" = "11" ]
check "the Git line is word for word the expected one, command included" [ "$(last_line "$OUT")" = "$want_line" ]
check "a line gives the sha256 of the handoff that went into the log" \
  [ "$(printf '%s\n' "$OUT" | grep -c '^Handoff sha256, recorded in the log: [0-9a-f]\{64\}$')" -eq 1 ]
check "the output is six lines" [ "$(printf '%s\n' "$OUT" | grep -c '')" -eq 6 ]
check "the close made no commit" [ "$(git rev-parse HEAD)" = "$c1" ]
check "the close staged nothing: the index holds what the owner staged" [ "$(git diff --cached --name-only)" = "staged.txt" ]
verdict "close ending: $(last_line "$OUT")"

say "The owner runs the printed command line, as printed."
cmd=${OUT##*To commit them: }
printf '      $ %s\n' "$cmd"
sh -c "$cmd" > "$WORK/commit.out" 2>&1
rc=$?
sed 's/^/      /' "$WORK/commit.out"
check "it exits 0" [ "$rc" -eq 0 ]
check "one new commit, on top of the old one" [ "$(git rev-parse HEAD^)" = "$c1" ]
check "its subject names the officeholder" [ "$(git log -1 --format=%s)" = "Succession: Sextant-001 closed" ]
outside=$(git show --name-only --format= HEAD | grep -v '^\.succession/' | grep -c '')
check "every file in it is under .succession/" [ "$outside" -eq 0 ]
for f in seat.json log.jsonl lineage.jsonl tenures/001-sextant/handoff.md tenures/001-sextant/lessons.md tenures/001-sextant/checkpoints.md; do
  check "it holds .succession/$f" git cat-file -e "HEAD:.succession/$f"
done
check "nothing under .succession/ is left uncommitted" [ -z "$(git status --porcelain --untracked-files=all -- .succession)" ]
check "the owner's staged file is still staged and was not committed" [ "$(git diff --cached --name-only)" = "staged.txt" ]
check "the owner's unstaged edit is still unstaged" [ "$(git diff --name-only)" = "a.txt" ]

run "verify.sh   (the handoff, now that .succession/ is committed)" "$SH" "$SCRIPTS/verify.sh"
check "the verdict does not depend on the commit: 2 claims, 1 pointers verified, 0 failed, 1 not checkable" \
  [ "$(last_line "$OUT")" = "2 claims, 1 pointers verified, 0 failed, 1 not checkable." ]
verdict "close, after the commit: $(last_line "$OUT") rc=$RC"

say "A close after the owner's stop phrase ends the same way."
quiet "$SH" "$SCRIPTS/log-append.sh" seat Astrolabe
quiet "$SH" "$SCRIPTS/log-append.sh" stand_down
check "stand_down prints no Git line" [ "$(git_lines "$OUT")" -eq 0 ]
write_handoff 002-astrolabe Astrolabe-002
quiet "$SH" "$SCRIPTS/log-append.sh" close "Second tenure" "Stopped by the owner."
check "the last line carries the command for Astrolabe-002" \
  [ "$(last_line "$OUT")" = 'Git: the state files in .succession/ are not committed yet. To commit them: git add .succession; git commit -m "Succession: Astrolabe-002 closed" -- .succession' ]

say "A seat vacated without a handoff prints no Git line."
quiet "$SH" "$SCRIPTS/verify.sh"
quiet "$SH" "$SCRIPTS/log-append.sh" seat Compass
quiet "$SH" "$SCRIPTS/log-append.sh" vacate "Left without a handoff"
check "vacate prints no Git line" [ "$(git_lines "$OUT")" -eq 0 ]

# second_project <folder>: another throwaway repository beside the first.
second_project() {
  mkdir "$WORK/$1" || exit 99
  cd "$WORK/$1" || exit 99
  git init -q . || exit 99
  git symbolic-ref HEAD refs/heads/main
  git config user.name "Test Owner"
  git config user.email "owner.invalid"
  git config commit.gpgsign false
  git config core.autocrlf "${SUCCESSION_TEST_AUTOCRLF:-false}"
  git config core.safecrlf false
  printf 'one\n' > a.txt
  c1=$(commit_all "Initial commit")
}

say "A project whose .gitignore lists .succession/: the line says so, and gives no command."
second_project ignored
printf '.succession/\n' > .gitignore
commit_all "Ignore .succession" > /dev/null
quiet "$SH" "$SCRIPTS/log-append.sh" seat Sextant
write_handoff 001-sextant Sextant-001
run "log-append.sh close \"Tenure in a project that ignores .succession/\"" "$SH" "$SCRIPTS/log-append.sh" close "Tenure in a project that ignores .succession/"
check "the last line says .succession/ is ignored" \
  [ "$(last_line "$OUT")" = "Git: .succession/ is ignored by git in this project, so there is nothing to commit." ]
check "no command line is printed" lacks "$OUT" "git add"
check "one line starts with Git:" [ "$(git_lines "$OUT")" -eq 1 ]
verdict "close ending, ignored: $(last_line "$OUT")"

say "Git set to hide untracked files, and the close run from a sub-folder: the line is the same."
second_project hidden
git config status.showUntrackedFiles no
quiet "$SH" "$SCRIPTS/log-append.sh" seat Sextant
write_handoff 001-sextant Sextant-001
mkdir sub
cd sub || exit 99
quiet "$SH" "$SCRIPTS/log-append.sh" close "Tenure closed from a sub-folder"
cd .. || exit 99
check "git status itself shows nothing here (the setting hides untracked files)" [ -z "$(git status --porcelain)" ]
check "the Git line still says the files are not committed, with the command" [ "$(last_line "$OUT")" = "$want_line" ]

finish
