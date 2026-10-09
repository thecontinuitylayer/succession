#!/bin/sh
# compact-mark.sh - PreCompact hook: a note in the log that the context
# is about to be compacted.
#
#   compact-mark.sh manual     (/compact; hooks.json passes the word on
#                              the "manual" matcher)
#   compact-mark.sh auto       (Claude Code compacts by itself)
#
# When, and only when, an officeholder holds the seat, it has
# log-append.sh add one entry to .succession/log.jsonl: type
# "checkpoint", with the fixed text "Context compacted (manual)." or
# "Context compacted (auto)." and a sentence saying that the plugin wrote
# it. No new entry type, so a log that holds it reads the same to every
# version of verify.sh. Nothing is written to the checkpoint note or to
# any other file.
#
# It must never hold up or stop a compaction:
#   - it always exits 0 (Claude Code takes exit code 2 from this hook as
#     "do not compact");
#   - it prints nothing on standard output, ever (Claude Code would take
#     text printed there as an instruction for the summary);
#   - log-append.sh waits at most three seconds for the lock on this
#     path, well inside this hook's ten;
#   - when the note cannot be written it says so in one line on standard
#     error and the compaction goes ahead without it.
#
# It does not read its standard input or the conversation transcript.
# Nothing is sent anywhere. In a project without .succession it does
# nothing. It asks git for the repository root; a compaction is rare, so
# this hook is not one of the two that are kept to shell builtins.
#
# POSIX sh. No network.

LC_ALL=C
export LC_ALL

exec 3>&2 > /dev/null 2>&1

trigger=${1-}
case $trigger in
  manual | auto) ;;
  *) exit 0 ;;
esac

# (CDPATH is cleared so that cd can neither go somewhere else nor print.)
unset CDPATH
start=$PWD
cd -P -- "${CLAUDE_PROJECT_DIR:-.}" || exit 0
command -v git || exit 0
root=$(git rev-parse --show-toplevel) || exit 0
[ -n "$root" ] || exit 0
S="$root/.succession"
[ -d "$S" ] || exit 0
[ -L "$S" ] && exit 0
[ -f "$S/seat.json" ] || exit 0
[ -L "$S/seat.json" ] && exit 0

# Only the status is needed here. log-append.sh reads the whole of
# seat.json again, under the lock, and refuses when nobody is seated.
status=
while IFS= read -r line || [ -n "$line" ]; do
  case $line in
    *'"status"'*:*'"'*'"'*)
      status=${line#*:}
      status=${status#*\"}
      status=${status%%\"*}
      ;;
  esac
done < "$S/seat.json"
[ "$status" = occupied ] || exit 0

here=${0%/*}
[ "$here" != "$0" ] || here=.
case $here in
  /* | [A-Za-z]:*) ;;
  *) here="$start/$here" ;;
esac

if ! why=$(cd "$root" && sh "$here/log-append.sh" compact "$trigger" 2>&1 > /dev/null); then
  why=${why%%"
"*}
  printf 'succession: the compaction (%s) was not noted in .succession/log.jsonl: %s\n' "$trigger" "${why#succession: }" >&3
fi
exit 0
