#!/bin/sh
# stand-down.sh - UserPromptSubmit hook: the owner's stop phrase.
#
# Fires when, and only when, the WHOLE submitted prompt, with spaces and
# line breaks trimmed from both ends, is
#
#     Stand down, <codename>
#
# for the officeholder now seated. Letter case is ignored, and one full
# stop or one exclamation mark straight after the codename is allowed,
# because dictation adds them. The phrase inside a longer prompt, inside
# a paste or inside a quoted block does nothing. When in doubt it does
# not fire.
#
# On a match it has log-append.sh append a stand_down entry and mark
# seat.json stood_down, then prints text that Claude Code adds to the
# model's context. The record is on disk before the model sees anything,
# so it exists even if the model ignores the text. log-append.sh waits at
# most three seconds for the lock on this path, well inside this hook's
# ten. If the record cannot be written, the hook says so twice: to the
# model, and to the owner directly, as a JSON document whose
# "systemMessage" Claude Code shows to the user. The text tells the
# officeholder to stop, to start nothing and call no skill, and to tell
# the owner that sending /succession:close writes the handoff and vacates
# the seat. The close is the owner's next move, not the model's.
#
# Claude Code passes hook input as one JSON document on standard input.
# The "prompt" field is examined in memory and is never written anywhere.
# The transcript_path field is never opened. Nothing is sent anywhere.
#
# This hook runs on every prompt, so the usual outcomes cost as little as
# possible. Starting a process is slow on Windows:
#   - no repository, or a repository without .succession: shell builtins
#     alone, no other process is started;
#   - nobody in the seat: the same;
#   - a seat is held and the prompt is not the phrase: one awk process;
#   - the prompt is the phrase: git confirms the repository root before
#     anything is written, as before.
#
# POSIX sh and awk. No jq, node or python. Always exits 0: this hook must
# never block a prompt.

LC_ALL=C
export LC_ALL

is_tenure_name() {
  case $1 in
    '' | *[!0-9a-z-]*) return 1 ;;
    [0-9]*-[a-z]*) return 0 ;;
  esac
  return 1
}

# Finds the project's .succession folder with shell builtins alone.
#
# Walks up from the current folder the way git does: the nearest folder
# that holds a .git entry is taken as the repository root.
#   returns 0: FOUND is <root>/.succession. It is a candidate: git still
#              confirms the root before anything is written.
#   returns 1: there is no repository here, or it has no .succession folder.
#   returns 2: cannot tell without git. That is the answer when GIT_DIR or
#              GIT_WORK_TREE is set, when the repository's own config
#              names a work tree, for a network path, and under Git Bash
#              for a path that is not on a drive (/tmp there is a mount
#              point, so its parent folders are not the real ones).
# Known difference from asking git: a folder whose .git holds a HEAD file
# but is not a usable repository is still taken as the root, where git
# would go on looking further up. The hook then stays silent.
find_state() {
  FOUND=
  [ -z "${GIT_DIR+x}${GIT_WORK_TREE+x}" ] || return 2
  fs_p=$PWD
  case $fs_p in
    //* | [!/]*) return 2 ;;
  esac
  fs_win=0
  case ${OS-}:${MSYSTEM-} in
    Windows*:* | *:MSYS* | *:MINGW* | *:UCRT* | *:CLANG*)
      fs_win=1
      case $fs_p in
        /[A-Za-z] | /[A-Za-z]/*) ;;
        *) return 2 ;;
      esac
      ;;
  esac
  [ "$fs_p" != / ] || fs_p=
  while :; do
    if [ -f "$fs_p/.git" ] || [ -e "$fs_p/.git/HEAD" ]; then
      if [ -f "$fs_p/.git/config" ]; then
        while IFS= read -r fs_line || [ -n "$fs_line" ]; do
          case $fs_line in
            *[Ww][Oo][Rr][Kk][Tt][Rr][Ee][Ee]*) return 2 ;;
          esac
        done < "$fs_p/.git/config"
      fi
      [ -d "$fs_p/.succession" ] || return 1
      FOUND="$fs_p/.succession"
      return 0
    fi
    case $fs_p in
      */*) fs_p=${fs_p%/*} ;;
      *) return 1 ;;
    esac
    if [ -z "$fs_p" ] && [ "$fs_win" -eq 1 ]; then
      return 1
    fi
  done
}

# The repository root, from git: ROOT.
git_root() {
  ROOT=
  command -v git > /dev/null 2>&1 || return 1
  ROOT=$(git rev-parse --show-toplevel 2> /dev/null) || return 1
  [ -n "$ROOT" ]
}

# Reads seat.json into SEAT_* without leaving the shell.
# Returns 1 when there is no seat.json, 2 when it cannot be trusted.
# A carriage return at the end of a line (a CRLF checkout) needs no
# handling here: every value is taken from between two double quotes.
read_seat() {
  SEAT_STATUS=
  SEAT_ORDINAL=
  SEAT_CODENAME=
  SEAT_TENURE=
  [ -e "$S/seat.json" ] || return 1
  [ -L "$S/seat.json" ] && return 2
  while IFS= read -r rs_line || [ -n "$rs_line" ]; do
    case $rs_line in
      *'"'*'"'*:*'"'*'"'*) ;;
      *) continue ;;
    esac
    rs_key=${rs_line#*\"}
    rs_key=${rs_key%%\"*}
    rs_val=${rs_line#*:}
    rs_val=${rs_val#*\"}
    rs_val=${rs_val%%\"*}
    case $rs_key in
      status) SEAT_STATUS=$rs_val ;;
      ordinal) SEAT_ORDINAL=$rs_val ;;
      codename) SEAT_CODENAME=$rs_val ;;
      tenure) SEAT_TENURE=$rs_val ;;
    esac
  done < "$S/seat.json"
  case $SEAT_STATUS in
    vacant | occupied | stood_down) ;;
    *) return 2 ;;
  esac
  case $SEAT_ORDINAL in
    '' | *[!0-9]*) return 2 ;;
  esac
  case $SEAT_CODENAME in
    '' | *[!A-Za-z0-9-]*) return 2 ;;
  esac
  [ "${#SEAT_CODENAME}" -le 32 ] || return 2
  is_tenure_name "$SEAT_TENURE" || return 2
  return 0
}

# Reads the hook's JSON document on standard input and exits 0 only if
# the top-level "prompt" string, trimmed, is the stop phrase, or the stop
# phrase followed by exactly one "." or one "!".
#
# The document is split at its double quotes, and the pieces are walked
# once, tracking which pieces are inside a string and how deeply the text
# between strings is nested. That way a "prompt" key inside another value,
# or the phrase inside another field, cannot match. A quote preceded by an
# odd number of backslashes is an escaped quote and does not end a string.
#
# The value is compared in its JSON-encoded form. The only things trimmed
# are spaces and the escapes \n, \r and \t. A value that carries any other
# escape (a quote, a backslash, a \u sequence) is not decoded and therefore
# cannot equal the phrase. Anything unexpected in the document means no
# match: a document over 64 KB, more than 256 punctuation marks between
# two strings, a second top-level "prompt", text after the closing brace.
prompt_is_stop_phrase() {
  awk -v code="$1" '
    BEGIN { want = "stand down, " tolower(code); big = 0; doc = "" }
    {
      if (big) next
      doc = doc $0 " "
      if (length(doc) > 65536) { big = 1; doc = "" }
    }
    # True when a piece ends with an odd number of backslashes.
    function escapes_next_quote(s,    len) {
      len = length(s)
      if (len == 0 || substr(s, len, 1) != "\\") return 0
      match(s, /\\+$/)
      return RLENGTH % 2
    }
    # The punctuation of a piece of text that is outside every string.
    function punctuation(s) {
      gsub(/[^][{},:]/, "", s)
      return s
    }
    # Walks that punctuation, keeping depth and state up to date.
    # Returns 0 when the document is not shaped as expected.
    function walk(s,    k, c) {
      if (length(s) > 256) return 0
      for (k = 1; k <= length(s); k++) {
        c = substr(s, k, 1)
        if (c == "{" || c == "[") {
          if (closed) return 0
          depth++
          if (depth == 1) {
            if (c != "{") return 0
            state = "key"
          } else {
            state = "other"
          }
        } else if (c == "}" || c == "]") {
          depth--
          if (depth < 0) return 0
          if (depth == 0) closed = 1
          state = "other"
        } else if (c == ",") {
          state = (depth == 1) ? "key" : "other"
        } else {
          state = "other"
        }
      }
      return 1
    }
    END {
      if (big) exit 1
      if (index(tolower(doc), want) == 0) exit 1
      pieces = split(doc, piece, "\"")
      depth = 0
      closed = 0
      state = ""
      count = 0
      value = ""
      if (punctuation(piece[1]) != "{") exit 1
      if (!walk("{")) exit 1
      i = 1
      while (i < pieces) {
        # piece[i + 1] opens a string. Find the piece that ends it.
        i++
        text = piece[i]
        plain = 1
        while (escapes_next_quote(piece[i])) {
          plain = 0
          i++
          if (i > pieces) exit 1
        }
        if (i >= pieces) exit 1
        i++
        after = punctuation(piece[i])
        if (state == "key") {
          if (substr(after, 1, 1) != ":") exit 1
          if (plain && text == "prompt") {
            if (after != ":") exit 1
            state = "prompt value"
            continue
          }
        } else if (state == "prompt value") {
          count++
          value = plain ? text : "\""
          state = "other"
        }
        if (!walk(after)) exit 1
      }
      if (count != 1 || depth != 0 || !closed) exit 1
      v = tolower(value)
      sub(/^( |\\[nrt])+/, "", v)
      sub(/( |\\[nrt])+$/, "", v)
      if (v == want || v == want "." || v == want "!") exit 0
      exit 1
    }
  '
}

seat_is_held() {
  case $SEAT_STATUS in
    occupied | stood_down) return 0 ;;
  esac
  return 1
}

# (CDPATH is cleared so that cd can neither go somewhere else nor print.)
unset CDPATH
start=$PWD
cd -P -- "${CLAUDE_PROJECT_DIR:-.}" > /dev/null 2>&1 || exit 0

find_state
case $? in
  0)
    S=$FOUND
    confirmed=0
    ;;
  1) exit 0 ;;
  *)
    git_root || exit 0
    S="$ROOT/.succession"
    [ -d "$S" ] || exit 0
    confirmed=1
    ;;
esac
[ -L "$S" ] && exit 0

read_seat || exit 0
seat_is_held || exit 0

command -v awk > /dev/null 2>&1 || exit 0
prompt_is_stop_phrase "$SEAT_CODENAME" || exit 0

# The prompt is the stop phrase. Nothing is written until git itself has
# named the repository root and the seat there reads the same.
if [ "$confirmed" -eq 0 ]; then
  candidate=$SEAT_CODENAME
  git_root || exit 0
  S="$ROOT/.succession"
  [ -d "$S" ] || exit 0
  [ -L "$S" ] && exit 0
  read_seat || exit 0
  seat_is_held || exit 0
  [ "$SEAT_CODENAME" = "$candidate" ] || exit 0
fi
root=$ROOT

name="$SEAT_CODENAME-$SEAT_ORDINAL"
here=${0%/*}
[ "$here" != "$0" ] || here=.
case $here in
  /* | [A-Za-z]:*) ;;
  *) here="$start/$here" ;;
esac
here=$(cd "$here" 2> /dev/null && pwd) || here=

recorded=
tell="that the stand-down is recorded"
failed=0
if [ "$SEAT_STATUS" = stood_down ]; then
  recorded="The stand-down was already recorded in .succession/log.jsonl and .succession/seat.json reads stood_down."
elif [ -n "$here" ] && record=$(cd "$root" && sh "$here/log-append.sh" stand_down 2>/dev/null); then
  entry=${record##*Log entry: }
  entry=${entry%%[!0-9a-f]*}
  recorded="The stand-down is recorded in .succession/log.jsonl (entry $entry) and .succession/seat.json now reads stood_down."
else
  recorded="WARNING: the stand-down could not be written to .succession/log.jsonl."
  tell="that the stand-down could not be recorded"
  failed=1
fi

text="Succession: the owner's whole prompt is the stop phrase for $name. $recorded $name stops the current work now and starts nothing new. $name does not write the handoff and does not call a skill or any other tool by itself. $name replies to the owner in one or two plain sentences, saying $tell and that sending /succession:close writes the handoff and vacates the seat."

if [ "$failed" -eq 0 ]; then
  printf '%s\n' "$text"
  exit 0
fi

# The stand-down is not on the record. The model is told, as above, and
# the owner is told directly as well: Claude Code shows "systemMessage"
# to the user, whatever the model then does. The text holds no character
# that JSON needs escaped (the name is letters, digits and hyphens).
printf '{"systemMessage":"Succession: WARNING. The stand-down of %s could not be written to .succession/log.jsonl: another write holds the lock, or the folder cannot be written to. It is NOT on the record. Send the stop phrase again.","hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$name" "$text"
exit 0
