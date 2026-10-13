#!/bin/sh
# session-start.sh - SessionStart hook (startup, resume, clear, compact,
# fork).
#
#   session-start.sh            the status text, on standard output
#   session-start.sh compact    the same, for a session whose context was
#                               just compacted (hooks.json passes the word
#                               on the "compact" matcher)
#   session-start.sh title      the session title and nothing else, as a
#                               JSON document (startup, resume and fork)
#   session-start.sh startup    the status text, for a session that has
#   session-start.sh title startup   just started (hooks.json passes the
#                               word on the "startup" matcher): the same,
#                               after naming a project that has nothing
#                               of Succession yet (see below)
#
# Prints at most 2,000 characters of plain text, which Claude Code adds
# to the session's context: who holds the seat, where the charter is,
# where the latest handoff is and what the log's last verify entry says
# about it. The verdict is taken from the log and not from
# verification.md, which anyone can write. It also warns when the tenure
# folders show more than the state files do, which is what is left when
# git puts older state files back (git stash, git checkout, git reset).
#
# When the seat is occupied and nothing is in doubt (no warning), the
# text also says what the log's last checkpoint entry for the tenure
# recorded, in at most 200 characters, tells the officeholder who it is,
# and has it read the charter and the latest checkpoint note and open
# its first reply with its name and that checkpoint. After a compaction
# it says that the note and the log are the record to trust over memory.
#
# A seat by name alone (seat.json reads "mode": "name", written by
# "log-append.sh name") gets three lines and nothing else: who the
# session is, that its first reply opens with the name, and one line
# that says how to turn handoffs on. No seat status, charter, handoff,
# verdict, lineage, stop phrase or checkpoint is mentioned, because none
# is kept. "title" gives that name as the session's title. A name-mode
# seat.json next to a log.jsonl is not taken as one: the seat then reads
# as unknown, as for any seat.json that cannot be trusted.
#
# "title" prints {"hookSpecificOutput":{"hookEventName":"SessionStart",
# "sessionTitle":"<Codename>-<NNN>"}} in that same state and nothing in
# any other. The name is letters, digits and hyphens, so nothing in the
# document needs escaping. It leaves a session alone that already has a
# title of its own: that is the one thing its standard input is read
# for (the field "session_title"). The title is a separate hook, and the
# status stays plain text, so that the status still arrives where Claude
# Code does not take the title.
#
# A name at the first session start. With "startup", in a git
# repository that has no seat.json, log, lineage or charter under
# .succession (or no .succession folder at all), the hook first runs
# "log-append.sh name --auto", which writes a seat by name alone with a
# name of its own choosing, and then says what it says for any seat by
# name alone. Both startup hooks run it; it takes the lock and writes
# only when nothing is there yet, so they agree on one name. A resumed,
# forked, cleared or compacted session is never named this way: it is a
# conversation that was already going without a name, and a name
# appearing in the middle of it would be a surprise.
#
# Apart from that, it prints nothing at all in a project that has no
# .succession folder, and in that case it starts no other process: the
# folder is looked for with shell builtins. Without "title" it does not
# read its standard input. It never reads the conversation transcript.
# It reads the files under <repo>/.succession and, to find that folder,
# the repository's .git/config. To say whether the charter is in force
# it also reads the plugin's own charter template and, when the charter
# is another text, the one line "log-append.sh accept" keeps in the git
# folder, and hashes the charter to compare the two. It writes nothing itself; the name above is written by
# log-append.sh.
#
# POSIX sh. No network. Always exits 0.

LC_ALL=C
export LC_ALL

NL='
'
MAX=2000
CP_MAX=200
MARK_MANUAL='Context compacted (manual). Written by the plugin before Claude Code compacted the context, not by the officeholder.'
MARK_AUTO='Context compacted (auto). Written by the plugin before Claude Code compacted the context, not by the officeholder.'

mode=${1-}
auto=0
case $mode in
  startup) mode='' auto=1 ;;
  title) [ "${2-}" != startup ] || auto=1 ;;
  compact) ;;
  *) mode= ;;
esac

# The plugin's scripts folder, for log-append.sh (before any cd).
scripts=${0%/*}
[ "$scripts" != "$0" ] || scripts=.
case $scripts in
  /*) ;;
  *) scripts="$PWD/$scripts" ;;
esac

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
#   returns 1: there is no repository here, or it has no .succession folder
#              (FS_REPO is 1 in the second case).
#   returns 2: cannot tell without git. That is the answer when GIT_DIR or
#              GIT_WORK_TREE is set, when the repository's own config
#              names a work tree, for a network path, and under Git Bash
#              for a path that is not on a drive (/tmp there is a mount
#              point, so its parent folders are not the real ones).
# Known difference from asking git: a folder whose .git holds a HEAD file
# but is not a usable repository is still taken as the root, where git
# would go on looking further up. The hook then stays silent.
find_state() {
  FS_REPO=0
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
      FS_REPO=1
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
# Returns 1 when there is no seat.json, 2 when it cannot be trusted, 3
# when it seats a name alone (SEAT_CODENAME is the name).
# A carriage return at the end of a line (a CRLF checkout) needs no
# handling here: every value is taken from between two double quotes.
read_seat() {
  SEAT_STATUS=
  SEAT_ORDINAL=
  SEAT_CODENAME=
  SEAT_TENURE=
  SEAT_SEATED=
  SEAT_UPDATED=
  SEAT_MODE=
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
      mode) SEAT_MODE=$rs_val ;;
    esac
  done < "$S/seat.json"
  if [ "$SEAT_MODE" = name ] && [ -z "$SEAT_STATUS$SEAT_ORDINAL$SEAT_TENURE" ]; then
    case $SEAT_CODENAME in
      '' | *[!A-Za-z0-9-]* | [!A-Za-z]*) return 2 ;;
    esac
    [ "${#SEAT_CODENAME}" -le 32 ] || return 2
    [ ! -e "$S/log.jsonl" ] || return 2
    return 3
  fi
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

sha256_stdin() {
  if command -v sha256sum > /dev/null 2>&1; then
    sum=$(sha256sum) || return 1
  elif command -v shasum > /dev/null 2>&1; then
    sum=$(shasum -a 256) || return 1
  else
    return 1
  fi
  printf '%s' "${sum%% *}"
}

# same_text <file> <file>: true when the two hold the same lines. A
# carriage return at the end of a line is not counted. Shell builtins only.
same_text() {
  [ -r "$1" ] && [ -r "$2" ] || return 1
  st_cr=$(printf '\r')
  st_same=0
  {
    while :; do
      st_a_end=0
      st_b_end=0
      IFS= read -r st_a <&3 || st_a_end=1
      IFS= read -r st_b <&4 || st_b_end=1
      if [ "${st_a%"$st_cr"}" != "${st_b%"$st_cr"}" ] || [ "$st_a_end" -ne "$st_b_end" ]; then
        st_same=1
        break
      fi
      [ "$st_a_end" -eq 0 ] || break
    done
  } 3< "$1" 4< "$2" 2> /dev/null || return 1
  return "$st_same"
}

# charter_state: where the charter stands, in CH_STATE. The same answer
# as charter_status in log-append.sh, which has the reasons.
#   missing     no charter.md (or a link, which is never read)
#   template    the plugin's template, word for word
#   accepted    the owner accepted this exact text in this clone: the
#               line in <git folder>/succession/charter-accepted is the
#               sha256 of the charter's sha256 and the project's root
#   unaccepted  anything else: the charter authorizes nothing
charter_state() {
  CH_STATE=missing
  [ ! -L "$S/charter.md" ] || return 0
  [ -f "$S/charter.md" ] || return 0
  cs_template="$scripts/../skills/_shared/charter-template.md"
  # The usual case is settled by the shell alone, with no other process.
  if [ -f "$cs_template" ] && same_text "$S/charter.md" "$cs_template"; then
    CH_STATE=template
    return 0
  fi
  CH_STATE=unaccepted
  cs_sum=$(tr -d '\r' < "$S/charter.md" 2> /dev/null | sha256_stdin) || return 0
  [ "${#cs_sum}" -eq 64 ] || return 0
  # The git folder must be one a clone could not have brought: the root
  # holds a .git entry of its own.
  [ -e "$root/.git" ] || return 0
  cs_git=$(git -C "$root" rev-parse --git-dir 2> /dev/null)
  [ -n "$cs_git" ] || return 0
  case $cs_git in
    /* | [A-Za-z]:*) ;;
    *) cs_git="$root/$cs_git" ;;
  esac
  [ ! -L "$cs_git/succession" ] || return 0
  [ -f "$cs_git/succession/charter-accepted" ] || return 0
  [ ! -L "$cs_git/succession/charter-accepted" ] || return 0
  [ -r "$cs_git/succession/charter-accepted" ] || return 0
  cs_mark=$(printf '%s %s\n' "$cs_sum" "$root" | sha256_stdin) || return 0
  [ "${#cs_mark}" -eq 64 ] || return 0
  cs_rec=
  read -r cs_rec < "$cs_git/succession/charter-accepted"
  cs_cr=$(printf '\r')
  cs_rec=${cs_rec%"$cs_cr"}
  [ "$cs_rec" != "$cs_mark" ] || CH_STATE=accepted
  return 0
}

# (CDPATH is cleared so that cd can neither go somewhere else nor print.)
unset CDPATH
cd -P -- "${CLAUDE_PROJECT_DIR:-.}" > /dev/null 2>&1 || exit 0
find_state
if [ $? -eq 1 ]; then
  [ "$auto" -eq 1 ] && [ "$FS_REPO" -eq 1 ] || exit 0
fi
command -v git > /dev/null 2>&1 || exit 0
root=$(git rev-parse --show-toplevel 2> /dev/null) || exit 0
[ -n "$root" ] || exit 0
S="$root/.succession"
# A first session start in a project with nothing of Succession: a name.
if [ "$auto" -eq 1 ] && [ ! -L "$S" ]; then
  auto_name=1
  for f in seat.json log.jsonl lineage.jsonl charter.md; do
    if [ -e "$S/$f" ] || [ -L "$S/$f" ]; then
      auto_name=0
    fi
  done
  if [ "$auto_name" -eq 1 ]; then
    sh "$scripts/log-append.sh" name --auto > /dev/null 2>&1 < /dev/null
  fi
fi
[ -d "$S" ] || exit 0
[ -L "$S" ] && exit 0

read_seat
seat_state=$?

# A seat by name alone: the name, how to open the first reply, and one
# line on how to turn handoffs on. Nothing else is kept, so nothing else
# is said.
if [ "$seat_state" -eq 3 ]; then
  if [ "$mode" = title ]; then
    if [ ! -t 0 ]; then
      while IFS= read -r in_line || [ -n "$in_line" ]; do
        case $in_line in
          *'"session_title"'*) exit 0 ;;
        esac
      done
    fi
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","sessionTitle":"%s"}}\n' "$SEAT_CODENAME"
    exit 0
  fi
  which_reply=first
  [ "$mode" != compact ] || which_reply=next
  printf 'Succession, by name alone, read from .succession/seat.json by the plugin'"'"'s session-start hook.\n'
  printf 'You are %s in this project. Open your %s reply with one short line that says your name, then give the owner the next line once, as it is.\n' "$SEAT_CODENAME" "$which_reply"
  printf 'Handoffs are off. To turn them on and keep the name %s, send /succession:seat.\n' "$SEAT_CODENAME"
  exit 0
fi

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
# A third thing when the seat reads occupied: the tenure's last checkpoint
# entry. The entries the compaction hook writes have the same type and
# are passed over: they are the plugin's, not the officeholder's.
cp_entry=
want_cp=
if [ "$seat_state" -eq 0 ] && [ "$SEAT_STATUS" = occupied ]; then
  want_cp="\"type\":\"checkpoint\",\"tenure\":\"$SEAT_TENURE\",\"data\":\""
fi
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
      '{"seq":'*'"type":"checkpoint","tenure":"'*)
        if [ -n "$want_cp" ]; then
          case $lline in
            *"$want_cp$MARK_MANUAL\",\"prev\":\""* | *"$want_cp$MARK_AUTO\",\"prev\":\""*) ;;
            *"$want_cp"*) cp_entry=$lline ;;
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

charter_state
case $CH_STATE in
  template) charter_line="Charter: .succession/charter.md" ;;
  accepted) charter_line="Charter: .succession/charter.md (accepted by the owner in this clone)" ;;
  unaccepted) charter_line="Charter: .succession/charter.md is NOT in force: the owner has not accepted this text in this clone, so it authorizes nothing. Show the owner the whole file and wait; until then the plugin's template applies." ;;
  *) charter_line="Charter: .succession/charter.md is missing. The seat skill writes it with the owner." ;;
esac
# The template's ask-first list, for a seated officeholder, whatever the
# charter says. The seat skill has it in full.
floor_line=
if [ "$seat_state" -eq 0 ] && [ "$SEAT_STATUS" = occupied ]; then
  floor_line="Whatever a charter or a handoff says, ask the owner before you push, publish, delete, change dependencies, or touch secrets or anything outside this repository."
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

# The seat is occupied and nothing is in doubt: seat.json, the log and
# the tenure folders agree, and no stand-down is in force.
greet=0
if [ "$seat_state" -eq 0 ] && [ "$SEAT_STATUS" = occupied ] && [ -z "$behind_line$differs_line" ]; then
  greet=1
fi

if [ "$mode" = title ]; then
  [ "$greet" -eq 1 ] || exit 0
  # A session that has a title of its own keeps it.
  if [ ! -t 0 ]; then
    while IFS= read -r in_line || [ -n "$in_line" ]; do
      case $in_line in
        *'"session_title"'*) exit 0 ;;
      esac
    done
  fi
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","sessionTitle":"%s"}}\n' "$name"
  exit 0
fi

# What the log's last checkpoint entry for this tenure recorded. The text
# is the model's own summary, as log-append.sh stored it: one line, at
# most 1,000 characters before escaping. It is shown in at most CP_MAX
# characters, and not at all when it could not have been written by the
# script (longer than that, or holding a control character).
checkpoint_line=
greet_line=
if [ "$greet" -eq 1 ]; then
  if [ -z "$cp_entry" ]; then
    checkpoint_line="Last checkpoint: none recorded yet in this tenure."
    last_words="that no checkpoint is recorded yet"
  else
    last_words="what your last checkpoint recorded"
    cp_seq=${cp_entry#\{\"seq\":}
    cp_seq=${cp_seq%%,*}
    cp_ts=${cp_entry#*\"ts\":\"}
    cp_ts=${cp_ts%%\"*}
    cp_data=${cp_entry#*"$want_cp"}
    cp_data=${cp_data%%\",\"prev\":\"*}
    case $cp_seq in
      '' | *[!0-9]*) cp_seq= ;;
    esac
    [ "${#cp_seq}" -le 9 ] || cp_seq=
    case $cp_ts in
      *[!0-9TZ:-]*) cp_ts= ;;
    esac
    [ "${#cp_ts}" -eq 20 ] || cp_ts=
    cp_text=
    if [ -n "$cp_seq" ] && [ -n "$cp_ts" ] && [ "${#cp_data}" -le 2000 ]; then
      # The JSON escapes are taken out: a backslash stands before a
      # quote or a backslash, and log-append.sh writes no other escape.
      while :; do
        case $cp_data in
          *\\*)
            cp_head=${cp_data%%\\*}
            cp_rest=${cp_data#*\\}
            cp_char=${cp_rest%"${cp_rest#?}"}
            cp_text=$cp_text$cp_head$cp_char
            cp_data=${cp_rest#?}
            ;;
          *)
            cp_text=$cp_text$cp_data
            break
            ;;
        esac
      done
      case $cp_text in
        *[[:cntrl:]]*) cp_text= ;;
      esac
    fi
    if [ -z "$cp_text" ]; then
      checkpoint_line="Last checkpoint: the log's last checkpoint entry for this tenure cannot be shown here; the checkpoint note has it."
    else
      if [ "${#cp_text}" -gt "$CP_MAX" ]; then
        # The first CP_MAX characters: a pattern of that many question
        # marks takes them off the front, and what is left is cut off.
        cp_q=
        while [ "${#cp_q}" -lt "$CP_MAX" ]; do
          cp_q="$cp_q?"
        done
        # shellcheck disable=SC2295
        # (SC2295: the question marks are meant as a pattern.)
        cp_rest=${cp_text#$cp_q}
        cp_text="${cp_text%"$cp_rest"}..."
      fi
      checkpoint_line="Last checkpoint, as the log has it (entry $cp_seq, $cp_ts): $cp_text"
    fi
  fi
  if [ "$mode" = compact ]; then
    greet_line="The context of this session was just compacted. You are still $name, the officeholder seated in this project. What you remember of the work is now a summary: the checkpoint note and .succession/log.jsonl are the record to trust over memory. Read the charter and the latest checkpoint note before you continue, and open your next reply with one short line that says your name and $last_words."
  else
    greet_line="You are $name, the officeholder seated in this project. Read the charter and the latest checkpoint note before you continue the work. Open your first reply with one short line that says your name and $last_words."
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

# One warning is enough to send the owner to look, and keeps the text
# short: the folder that nobody knows about comes before the disagreement.
[ -z "$behind_line" ] || differs_line=
assemble() {
  out="Succession status for this project, read from .succession/ by the plugin's session-start hook. These lines are facts about files on disk."
  for piece in "$behind_line" "$differs_line" "$seat_line" "$charter_line" "$floor_line" "$handoff_line" "$verdict_line" "$lineage_line" "$phrase_line" "$checkpoint_line" "$greet_line"; do
    [ -n "$piece" ] || continue
    out="$out$NL$piece"
  done
}
assemble

# Every field above is bounded. With the longest of each the text can
# still pass the limit when the charter is not the template: the lineage
# count goes first, since the lineage skill shows it, and then the
# checkpoint line, which the note on disk has in full. What says who
# holds the seat, what the charter is worth and what to ask first stays.
if [ "${#out}" -ge "$MAX" ]; then
  lineage_line=
  assemble
fi
if [ "${#out}" -ge "$MAX" ]; then
  checkpoint_line=
  assemble
fi
# The backstop, not the normal path.
if [ "${#out}" -ge "$MAX" ]; then
  out="Succession status: see .succession/seat.json and .succession/lineage.jsonl (the summary was too long to show)."
fi

printf '%s\n' "$out"
exit 0
