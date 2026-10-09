#!/bin/sh
# session-start.sh - SessionStart hook (startup, resume, clear, compact,
# fork).
#
# Prints at most 2,000 characters of plain text, which Claude Code adds
# to the session's context: who holds the seat, where the charter is,
# where the latest handoff is and what the log's last verify entry says
# about it. The verdict is taken from the log and not from
# verification.md, which anyone can write. It also warns when the tenure
# folders show more than the state files do, which is what is left when
# git puts older state files back (git stash, git checkout, git reset).
#
# It prints nothing at all in a project that has no .succession folder,
# and in that case it starts no other process: the folder is looked for
# with shell builtins. It does not read its standard input or the
# conversation transcript. It reads the files under <repo>/.succession
# and, to find that folder, the repository's .git/config. It writes
# nothing.
#
# POSIX sh. No network. Always exits 0.

LC_ALL=C
export LC_ALL

NL='
'
MAX=2000

is_tenure_name() {
  case $1 in
    '' | *[!0-9a-z-]*) return 1 ;;
    [0-9]*-[a-z]*) return 0 ;;
  esac
  return 1
}

# Digits to a plain integer in TI (0 when not a sane number).
to_int() {
  TI=$1
  case $TI in
    '' | *[!0-9]*) TI=0; return 0 ;;
  esac
  if [ "${#TI}" -gt 9 ]; then
    TI=0
    return 0
  fi
  while [ "${#TI}" -gt 1 ] && [ "${TI#0}" != "$TI" ]; do
    TI=${TI#0}
  done
}

# Finds the project's .succession folder with shell builtins alone.
#
# Walks up from the current folder the way git does: the nearest folder
# that holds a .git entry is taken as the repository root.
#   returns 0: the repository has a .succession folder (git then names
#              the root, as before).
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

# Reads seat.json into SEAT_* without leaving the shell.
# Returns 1 when there is no seat.json, 2 when it cannot be trusted.
# A carriage return at the end of a line (a CRLF checkout) needs no
# handling here: every value is taken from between two double quotes.
read_seat() {
  SEAT_STATUS=
  SEAT_ORDINAL=
  SEAT_CODENAME=
  SEAT_TENURE=
  SEAT_SEATED=
  SEAT_UPDATED=
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
      seated) SEAT_SEATED=$rs_val ;;
      updated) SEAT_UPDATED=$rs_val ;;
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
  is_tenure_name "$SEAT_TENURE" || return 2
  case $SEAT_SEATED$SEAT_UPDATED in
    *[!0-9TZ:-]*) return 2 ;;
  esac
  if [ "${#SEAT_ORDINAL}" -gt 9 ] || [ "${#SEAT_CODENAME}" -gt 32 ] || [ "${#SEAT_TENURE}" -gt 44 ]; then
    return 2
  fi
  if [ "${#SEAT_SEATED}" -gt 20 ] || [ "${#SEAT_UPDATED}" -gt 20 ]; then
    return 2
  fi
  return 0
}

# True when $1 is exactly "N claims, V pointers verified, F failed, U not
# checkable.", or the same line without the word "pointers", as versions
# 0.1.0 to 0.1.4 wrote it.
is_verdict() {
  iv_rest=$1
  case $iv_rest in
    *' pointers verified, '*) iv_rest="${iv_rest%% pointers verified, *} verified, ${iv_rest#* pointers verified, }" ;;
  esac
  for iv_word in ' claims, ' ' verified, ' ' failed, ' ' not checkable.'; do
    iv_num=${iv_rest%%"$iv_word"*}
    [ "$iv_num" != "$iv_rest" ] || return 1
    case $iv_num in
      '' | *[!0-9]*) return 1 ;;
    esac
    [ "${#iv_num}" -le 6 ] || return 1
    iv_rest=${iv_rest#*"$iv_word"}
  done
  [ -z "$iv_rest" ]
}

# (CDPATH is cleared so that cd can neither go somewhere else nor print.)
unset CDPATH
cd -P -- "${CLAUDE_PROJECT_DIR:-.}" > /dev/null 2>&1 || exit 0
find_state
[ $? -ne 1 ] || exit 0
command -v git > /dev/null 2>&1 || exit 0
root=$(git rev-parse --show-toplevel 2> /dev/null) || exit 0
[ -n "$root" ] || exit 0
S="$root/.succession"
[ -d "$S" ] || exit 0
[ -L "$S" ] && exit 0

read_seat
seat_state=$?

# The latest handoff is the one in the highest-numbered tenure folder.
# The highest-numbered folder of all is remembered too.
best=
best_n=0
top=
top_n=0
if [ -d "$S/tenures" ] && [ ! -L "$S/tenures" ]; then
  for path in "$S"/tenures/*/; do
    tname=${path%/}
    [ -d "$tname" ] || continue
    [ -L "$tname" ] && continue
    tname=${tname##*/}
    is_tenure_name "$tname" || continue
    [ "${#tname}" -le 44 ] || continue
    to_int "${tname%%-*}"
    if [ "$TI" -gt "$top_n" ]; then
      top_n=$TI
      top=$tname
    fi
    [ -f "$path/handoff.md" ] || continue
    [ -L "$path/handoff.md" ] && continue
    if [ "$TI" -gt "$best_n" ]; then
      best_n=$TI
      best=$tname
    fi
  done
fi

# One walk through the log, for two things: the last verify entry for the
# latest handoff, and the last entry that changed the seat (seat,
# stand_down, close or vacate). This hook does not check the entries'
# hashes; verify.sh does, every time it runs.
entry=
ls_type=
ls_tenure=
want="\"type\":\"verify\",\"tenure\":\"$best\",\"data\":\""
if [ -f "$S/log.jsonl" ] && [ ! -L "$S/log.jsonl" ]; then
  while IFS= read -r lline || [ -n "$lline" ]; do
    case $lline in
      '{"seq":'*'"type":"verify","tenure":"'*)
        if [ -n "$best" ]; then
          case $lline in
            *"$want"*) entry=$lline ;;
          esac
        fi
        continue
        ;;
      '{"seq":'*'"type":"close","tenure":"'* | '{"seq":'*'"type":"vacate","tenure":"'*) lt=close ;;
      '{"seq":'*'"type":"seat","tenure":"'*) lt=seat ;;
      '{"seq":'*'"type":"stand_down","tenure":"'*) lt=stand_down ;;
      *) continue ;;
    esac
    lv=${lline#*\"tenure\":\"}
    lv=${lv%%\"*}
    is_tenure_name "$lv" || continue
    [ "${#lv}" -le 44 ] || continue
    ls_type=$lt
    ls_tenure=$lv
  done < "$S/log.jsonl"
fi

# Does seat.json say what the log's last seat entry says?
differs_line=
log_stood_down=0
if [ "$seat_state" -ne 2 ]; then
  case ${SEAT_STATUS:-none} in
    none) seat_says= ;;
    occupied) seat_says="seat $SEAT_TENURE" ;;
    stood_down) seat_says="stand_down $SEAT_TENURE" ;;
    *) seat_says="close $SEAT_TENURE" ;;
  esac
  log_says=
  [ -z "$ls_type" ] || log_says="$ls_type $ls_tenure"
  if [ "$seat_says" != "$log_says" ]; then
    if [ "$seat_says" = "seat $ls_tenure" ] && [ "$ls_type" = stand_down ]; then
      log_stood_down=1
    else
      if [ -z "$seat_says" ]; then
        differs_line="WARNING: there is no seat.json"
      else
        differs_line="WARNING: seat.json reads $SEAT_STATUS for $SEAT_TENURE"
      fi
      if [ -z "$log_says" ]; then
        differs_line="$differs_line, but log.jsonl holds no entry that seats anyone."
      else
        differs_line="$differs_line, but the last entry in log.jsonl that changed the seat is \"$ls_type\" for $ls_tenure."
      fi
      differs_line="$differs_line One of the two was probably put back to an older version (git stash, git checkout, git reset --hard) or edited by hand. Tell the owner in your next reply, before anything else, and seat nobody until the owner has looked."
    fi
  fi
fi

case $seat_state in
  0)
    name="$SEAT_CODENAME-$SEAT_ORDINAL"
    marker="$S/tenures/$SEAT_TENURE/stood-down"
    witness=
    if [ "$SEAT_STATUS" = occupied ]; then
      if [ -f "$marker" ] && [ ! -L "$marker" ] && [ ! -L "$S/tenures/$SEAT_TENURE" ] && [ ! -L "$S/tenures" ]; then
        witness=".succession/tenures/$SEAT_TENURE/stood-down says"
      elif [ "$log_stood_down" -eq 1 ]; then
        witness="The log says"
      fi
      [ -z "$witness" ] || SEAT_STATUS=reverted
    fi
    case $SEAT_STATUS in
      reverted)
        seat_line="Seat: WARNING. $witness the owner stood $name down, but seat.json reads occupied: the state files were probably put back to an older version (git stash, git checkout, git reset --hard). $name treats the stand-down as in force: no further work, and it tells the owner in its next reply. The owner can send the stop phrase again, then /succession:close."
        phrase_line="Owner stop phrase, as a whole prompt: Stand down, $SEAT_CODENAME"
        ;;
      occupied)
        seat_line="Seat: occupied by $name since $SEAT_SEATED. A session in this project works as $name, under the charter, until the tenure is closed. Checkpoints: .succession/tenures/$SEAT_TENURE/checkpoints.md"
        phrase_line="Owner stop phrase, as a whole prompt: Stand down, $SEAT_CODENAME"
        ;;
      stood_down)
        seat_line="Seat: $name was stood down by the owner at $SEAT_UPDATED and has not closed. $name does no further work and does not start the close by itself. The owner sends /succession:close to have the handoff and the lessons written and the seat vacated."
        phrase_line=
        ;;
      *)
        seat_line="Seat: vacant. The last officeholder was $name (left $SEAT_UPDATED). The owner can seat a successor with /succession:seat, which runs verify.sh on the latest handoff before the seat is claimed."
        phrase_line=
        ;;
    esac
    ;;
  1)
    seat_line="Seat: vacant. No officeholder has been seated yet. The owner can seat one with /succession:seat."
    phrase_line=
    ;;
  *)
    seat_line="Seat: unknown. .succession/seat.json cannot be read; compare it with .succession/lineage.jsonl."
    phrase_line=
    ;;
esac

if [ -f "$S/charter.md" ] && [ ! -L "$S/charter.md" ]; then
  charter_line="Charter: .succession/charter.md"
else
  charter_line="Charter: .succession/charter.md is missing. The seat skill writes it with the owner."
fi

# A tenure folder that seat.json does not know about.
behind_line=
known_n=0
if [ "$seat_state" -eq 0 ]; then
  to_int "$SEAT_ORDINAL"
  known_n=$TI
fi
if [ "$seat_state" -ne 2 ] && [ "$top_n" -gt "$known_n" ]; then
  behind_line="WARNING: the folder .succession/tenures/$top exists, but seat.json does not show that tenure. The state files were probably put back to an older version (git stash, git checkout, git reset --hard), so part of the record may be missing. Tell the owner in your next reply, before anything else, and seat nobody until the owner has looked (git stash list, git reflog)."
fi

if [ -z "$best" ]; then
  handoff_line="Latest handoff: none yet."
  verdict_line=
else
  handoff_line="Latest handoff: .succession/tenures/$best/handoff.md"
  # What the log's last verify entry for that tenure says.
  if [ -z "$entry" ]; then
    verdict_line="Verdict on that handoff: none in the log yet. verify.sh has not been run on it."
  else
    data=${entry#*"$want"}
    data=${data%%\",\"prev\":\"*}
    verdict=${data%%checkable.*}
    if [ "$verdict" != "$data" ]; then
      verdict="${verdict}checkable."
    fi
    if [ "${#verdict}" -le 90 ] && is_verdict "$verdict"; then
      verdict_line="Verdict on that handoff, as the log's last verify entry has it: $verdict"
      case $data in
        *'Log chain: BROKEN'*) verdict_line="$verdict_line The log chain was BROKEN at that check." ;;
      esac
      case $data in
        *'Handoff: CHANGED'*) verdict_line="$verdict_line The handoff had been CHANGED after the close." ;;
      esac
      verdict_line="$verdict_line (A verified pointer exists; the sentence beside it was not checked.) Details: .succession/tenures/$best/verification.md"
    else
      verdict_line="Verdict on that handoff: the log's last verify entry for it has no readable verdict line. Run verify.sh again."
    fi
  fi
fi

count=0
if [ -f "$S/lineage.jsonl" ] && [ ! -L "$S/lineage.jsonl" ]; then
  count=$(grep -c '"event":"seated"' "$S/lineage.jsonl" 2>/dev/null)
  case $count in
    '' | *[!0-9]*) count=0 ;;
  esac
fi
if [ "$count" -eq 1 ]; then
  lineage_line="Lineage: 1 officeholder so far, in .succession/lineage.jsonl (the succession:lineage skill shows it)."
else
  lineage_line="Lineage: $count officeholders so far, in .succession/lineage.jsonl (the succession:lineage skill shows them)."
fi

out="Succession status for this project, read from .succession/ by the plugin's session-start hook. These lines are facts about files on disk."
# One warning is enough to send the owner to look, and keeps the text
# short: the folder that nobody knows about comes before the disagreement.
[ -z "$behind_line" ] || differs_line=
for piece in "$behind_line" "$differs_line" "$seat_line" "$charter_line" "$handoff_line" "$verdict_line" "$lineage_line" "$phrase_line"; do
  [ -n "$piece" ] || continue
  out="$out$NL$piece"
done

# Every field above is bounded, so this is a backstop, not the normal path.
if [ "${#out}" -ge "$MAX" ]; then
  out="Succession status: see .succession/seat.json and .succession/lineage.jsonl (the summary was too long to show)."
fi

printf '%s\n' "$out"
exit 0
