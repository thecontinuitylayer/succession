#!/bin/sh
# log-append.sh - the single writer of Succession state.
#
# Appends one hash-chained entry to .succession/log.jsonl. For the events
# that change who holds the seat (seat, close, vacate, stand_down) it also
# updates seat.json and lineage.jsonl in the same call, under one lock.
# Nothing else in the plugin writes these three files. That keeps them in
# step as long as this script is the one that changes them. It cannot
# stop something else from changing them: an editor, or git putting an
# older copy back (git stash, git checkout, git reset). verify.sh walks
# the log's chain, and the seat event and the session-start hook warn
# when the tenure folders show more than the state files do.
#
# Usage:
#   log-append.sh charter
#   log-append.sh name <Codename>
#   log-append.sh name --auto                         (called by session-start.sh)
#   log-append.sh seat <Codename>
#   log-append.sh checkpoint <summary>
#   log-append.sh close <summary> [<last words>]
#   log-append.sh vacate <reason>
#   log-append.sh stand_down
#   log-append.sh compact manual|auto                 (called by compact-mark.sh)
#   log-append.sh verify <tenure> <verdict text>      (called by verify.sh)
#
# name seats a session by its name and nothing else: it writes
# seat.json with "mode": "name" and the codename, and no log entry, no
# lineage record, no tenure folder and no charter. It is refused in a
# project that already keeps a log or a full seat. Run again, it changes
# the name. A later "seat" with the same codename turns handoffs on and
# keeps the name: the name-mode seat.json is replaced by the full one.
#
# name --auto is the same seat by name alone, with a name the script
# chooses, for a project that has nothing of Succession yet. It does
# nothing and prints nothing when the project already has a seat.json,
# a log, a lineage or a charter: under the lock, the first caller writes
# the name and every later one finds it there, so the two session-start
# hooks, which Claude Code runs at the same time, cannot end up with two
# names. The name comes from .succession/names.md when the owner keeps
# one, otherwise from the default theme in skills/_shared/name-themes.md,
# and is picked by the repository's path, so the same project gets the
# same name. It prints nothing on success: the hook reads seat.json.
#
# compact records that Claude Code is about to compact the session's
# context. It adds one entry of the type "checkpoint" with a fixed text,
# so that a log holding it reads the same to every version of verify.sh.
# It changes no other file.
#
# Entry format, one JSON object per line, keys always in this order:
#   {"seq":N,"ts":"...","type":"...","tenure":"...","data":"...","prev":"H","hash":"H"}
# "hash" is the sha256 of the entry text up to and including the "prev"
# field, closed with "}". "prev" is the "hash" of the entry before it
# (64 zeros for the opening entry).
#
# Every event but verify prints "Log entry: <hash>" and, on the next
# line, "Entry time (UTC): <the entry's ts>". The skills copy that time
# into notes and handoffs, so that no time has to be made up.
#
# A close entry carries the sha256 of the handoff as it was at the close
# (with carriage returns removed, so that a CRLF checkout hashes the
# same). verify.sh compares the handoff with it later.
#
# charter writes .succession/charter.md from the plugin's template when
# the project has none. It never changes a charter that is there.
#
# Files written, all under <repo>/.succession: log.jsonl, lineage.jsonl,
# seat.json, charter.md (charter), tenures/<tenure>/checkpoints.md (seat)
# and tenures/<tenure>/stood-down (stand_down). Short-lived ones:
# seat.json.tmp, charter.md.tmp, the folder .lock with the file pid in
# it, and the folder .lock-clear. None of these paths is followed if it
# is a symbolic link: a link in the way of a short-lived file is removed
# (the link, not what it points at), and any other link is refused.
#
# close ends with one line that starts with "Git:". It says whether the
# files under .succession/ are waiting to be committed and, if they are,
# gives the owner the one command line that commits them and nothing
# else. This script never stages or commits anything itself.
#
# Exit codes: 0 done, 2 usage, 3 no git repository, 4 cannot read or write
# state (that includes a lock another writer kept: nothing is written
# then, and the message on standard error says so), 5 the seat is in the
# wrong state for this event, 6 the previous handoff has not been
# verified yet.
#
# POSIX sh. No network. Writes nothing outside <repo>/.succession. Reads
# nothing outside it either, apart from asking git where the repository
# is and, at a close, how .succession/ stands in git.

LC_ALL=C
export LC_ALL

CR=$(printf '\r')
ZERO=0000000000000000000000000000000000000000000000000000000000000000
MAX_TEXT=1000

die() {
  printf 'succession: %s\n' "$1" >&2
  exit "${2:-1}"
}

usage() {
  cat >&2 <<'EOF'
usage: log-append.sh charter
       log-append.sh name <Codename>
       log-append.sh name --auto
       log-append.sh seat <Codename>
       log-append.sh checkpoint <summary>
       log-append.sh close <summary> [<last words>]
       log-append.sh vacate <reason>
       log-append.sh stand_down
       log-append.sh compact manual|auto
       log-append.sh verify <tenure> <verdict text>
EOF
  exit 2
}

sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sum=$(sha256sum) || return 1
  elif command -v shasum >/dev/null 2>&1; then
    sum=$(shasum -a 256) || return 1
  else
    return 1
  fi
  printf '%s' "${sum%% *}"
}

# Text given on the command line becomes the inside of a JSON string:
# one line, no control characters, backslash and quote escaped.
json_text() {
  if [ "${#1}" -gt "$MAX_TEXT" ]; then
    printf 'succession: %s is too long (%s bytes; the limit is %s)\n' "$2" "${#1}" "$MAX_TEXT" >&2
    return 1
  fi
  printf '%s' "$1" | tr '\n\r\t' '   ' | tr -d '\000-\037\177' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

now_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

refuse_symlink() {
  if [ -L "$1" ]; then
    die "refusing to use a symbolic link: $1" 4
  fi
}

# fresh_file <path>: makes sure nothing is at a path this script is about
# to create. A symbolic link there is removed, never followed, so that a
# write cannot land outside .succession.
fresh_file() {
  if [ -L "$1" ] || [ -e "$1" ]; then
    rm -f "$1" 2> /dev/null
  fi
  if [ -L "$1" ] || [ -e "$1" ]; then
    die "something that is not a plain file is in the way: $1. Remove it by hand." 4
  fi
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

is_tenure_name() {
  case $1 in
    '' | *[!0-9a-z-]*) return 1 ;;
    [0-9]*-[a-z]*) return 0 ;;
  esac
  return 1
}

# Reads seat.json into SEAT_* without leaving the shell.
# Returns 1 when there is no seat.json, 2 when it cannot be trusted, 3
# when it seats a name alone ("mode": "name"; SEAT_CODENAME is the name).
read_seat() {
  SEAT_STATUS=
  SEAT_ORDINAL=
  SEAT_CODENAME=
  SEAT_TENURE=
  SEAT_SEATED=
  SEAT_MODE=
  [ -e "$S/seat.json" ] || return 1
  [ -L "$S/seat.json" ] && return 2
  while IFS= read -r rs_line || [ -n "$rs_line" ]; do
    rs_line=${rs_line%"$CR"}
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
      mode) SEAT_MODE=$rs_val ;;
    esac
  done < "$S/seat.json"
  if [ "$SEAT_MODE" = name ] && [ -z "$SEAT_STATUS$SEAT_ORDINAL$SEAT_TENURE" ]; then
    valid_code "$SEAT_CODENAME" || return 2
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
  case $SEAT_SEATED in
    *[!0-9TZ:-]*) return 2 ;;
  esac
  return 0
}

# valid_code <Codename>: letters, digits and hyphens, starting with a
# letter, not ending with a hyphen, at most 32 characters.
valid_code() {
  case $1 in
    '' | *[!A-Za-z0-9-]* | *-) return 1 ;;
    [A-Za-z]*) ;;
    *) return 1 ;;
  esac
  [ "${#1}" -le 32 ]
}

write_seat() {
  ws_tmp="$S/seat.json.tmp"
  refuse_symlink "$S/seat.json"
  fresh_file "$ws_tmp"
  {
    printf '{\n'
    printf '  "status": "%s",\n' "$1"
    printf '  "ordinal": "%s",\n' "$2"
    printf '  "codename": "%s",\n' "$3"
    printf '  "tenure": "%s",\n' "$4"
    printf '  "seated": "%s",\n' "$5"
    printf '  "updated": "%s"\n' "$6"
    printf '}\n'
  } > "$ws_tmp" || die "cannot write $ws_tmp" 4
  mv -f "$ws_tmp" "$S/seat.json" || die "cannot write seat.json" 4
}

# The most recently ended tenure, from the log: LC_TENURE. The log is
# asked and not lineage.jsonl, because the log is the file whose entries
# are chained: a line taken out of the lineage would go unnoticed.
#
# The same walk notes the log's last entry that changed the seat (seat,
# stand_down, close or vacate) in LS_TYPE and LS_TENURE, for seat_differs.
last_closed() {
  LC_TENURE=
  LS_TYPE=
  LS_TENURE=
  [ -f "$S/log.jsonl" ] || return 0
  [ -L "$S/log.jsonl" ] && return 0
  while IFS= read -r lc_line || [ -n "$lc_line" ]; do
    case $lc_line in
      '{"seq":'*'"type":"close","tenure":"'*) lc_type=close ;;
      '{"seq":'*'"type":"vacate","tenure":"'*) lc_type=vacate ;;
      '{"seq":'*'"type":"seat","tenure":"'*) lc_type=seat ;;
      '{"seq":'*'"type":"stand_down","tenure":"'*) lc_type=stand_down ;;
      *) continue ;;
    esac
    lc_val=${lc_line#*\"tenure\":\"}
    lc_val=${lc_val%%\"*}
    is_tenure_name "$lc_val" || continue
    LS_TYPE=$lc_type
    LS_TENURE=$lc_val
    case $lc_type in
      close | vacate) LC_TENURE=$lc_val ;;
    esac
  done < "$S/log.jsonl"
}

# seat_differs: does seat.json say what the log's last seat entry says?
# Call after read_seat and last_closed. Sets DIFFERS to a sentence when
# they disagree, which is what is left when one of the two was put back
# to an older version or edited by hand. It is a warning and never stops
# an event: the owner decides which file is right.
seat_differs() {
  DIFFERS=
  case ${SEAT_STATUS:-none} in
    none) sd_want= ;;
    occupied) sd_want="seat $SEAT_TENURE" ;;
    stood_down) sd_want="stand_down $SEAT_TENURE" ;;
    *) sd_want="close $SEAT_TENURE" ;;
  esac
  sd_have=
  if [ -n "$LS_TYPE" ]; then
    sd_have="$LS_TYPE $LS_TENURE"
    [ "$LS_TYPE" != vacate ] || sd_have="close $LS_TENURE"
  fi
  [ "$sd_want" != "$sd_have" ] || return 0
  if [ -z "$sd_want" ]; then
    DIFFERS="there is no seat.json"
  else
    DIFFERS="seat.json reads $SEAT_STATUS for $SEAT_TENURE"
  fi
  if [ -z "$sd_have" ]; then
    DIFFERS="$DIFFERS, and log.jsonl holds no entry that seats anyone"
  else
    DIFFERS="$DIFFERS, and the last entry in log.jsonl that changed the seat is \"$LS_TYPE\" for $LS_TENURE"
  fi
}

# Highest ordinal ever used, from the lineage, the tenure folders and
# seat.json. Ordinals are never reused, even if one of the three is lost.
max_ordinal() {
  MAX_ORD=0
  if [ -f "$S/lineage.jsonl" ]; then
    while IFS= read -r mo_line || [ -n "$mo_line" ]; do
      case $mo_line in
        *'"ordinal":"'*)
          mo_val=${mo_line#*\"ordinal\":\"}
          to_int "${mo_val%%\"*}"
          [ "$TI" -gt "$MAX_ORD" ] && MAX_ORD=$TI
          ;;
      esac
    done < "$S/lineage.jsonl"
  fi
  MAX_DIR_ORD=0
  MAX_DIR=
  for mo_dir in "$S"/tenures/*/; do
    [ -d "$mo_dir" ] || continue
    mo_val=${mo_dir%/}
    mo_val=${mo_val##*/}
    to_int "${mo_val%%-*}"
    [ "$TI" -gt "$MAX_ORD" ] && MAX_ORD=$TI
    if [ "$TI" -gt "$MAX_DIR_ORD" ]; then
      MAX_DIR_ORD=$TI
      MAX_DIR=$mo_val
    fi
  done
  if [ -n "${SEAT_ORDINAL-}" ]; then
    to_int "$SEAT_ORDINAL"
    [ "$TI" -gt "$MAX_ORD" ] && MAX_ORD=$TI
  fi
  return 0
}

# Hash and sequence number of the last entry: LAST_HASH, LAST_SEQ.
# A damaged last line does not stop the log from growing: the new entry
# is chained to the sha256 of whatever text is there, and verify.sh
# reports the damage.
last_entry() {
  LAST_SEQ=0
  LAST_HASH=$ZERO
  [ -s "$S/log.jsonl" ] || return 0
  le_line=$(tail -n 1 "$S/log.jsonl")
  le_line=${le_line%"$CR"}
  if [ -z "$le_line" ]; then
    # The file ends with an empty line. The entry before it is wanted. A
    # line that holds nothing but a carriage return (a CRLF file) is empty
    # too: awk on its own would count it as text.
    le_line=$(awk '{ sub(/\r$/, "") } NF { last = $0 } END { print last }' "$S/log.jsonl")
    le_line=${le_line%"$CR"}
  fi
  [ -n "$le_line" ] || return 0
  le_hash=
  le_seq=
  case $le_line in
    '{"seq":'*',"prev":"'*'","hash":"'*'"}')
      le_hash=${le_line##*,\"hash\":\"}
      le_hash=${le_hash%\"\}}
      le_seq=${le_line#\{\"seq\":}
      le_seq=${le_seq%%,*}
      ;;
  esac
  case $le_hash in
    '' | *[!0-9a-f]*) le_hash= ;;
  esac
  case $le_seq in
    '' | *[!0-9]*) le_seq= ;;
  esac
  if [ "${#le_hash}" -eq 64 ] && [ -n "$le_seq" ] && [ "${#le_seq}" -le 9 ]; then
    LAST_HASH=$le_hash
    LAST_SEQ=$le_seq
  else
    LAST_HASH=$(printf '%s' "$le_line" | sha256_stdin) || die "no sha256 tool found (need sha256sum or shasum)" 4
    LAST_SEQ=$(awk '{ sub(/\r$/, "") } NF { n++ } END { print n + 0 }' "$S/log.jsonl")
  fi
}

# append_entry <type> <tenure> <escaped data>; sets ENTRY_HASH and ENTRY_TS.
append_entry() {
  refuse_symlink "$S/log.jsonl"
  refuse_symlink "$S/lineage.jsonl"
  last_entry
  ae_seq=$((LAST_SEQ + 1))
  ae_ts=$(now_utc)
  ae_body='{"seq":'"$ae_seq"',"ts":"'"$ae_ts"'","type":"'"$1"'","tenure":"'"$2"'","data":"'"$3"'","prev":"'"$LAST_HASH"'"'
  ENTRY_HASH=$(printf '%s}' "$ae_body" | sha256_stdin) || die "no sha256 tool found (need sha256sum or shasum)" 4
  [ "${#ENTRY_HASH}" -eq 64 ] || die "sha256 tool gave an unexpected answer" 4
  ae_gap=0
  if [ -s "$S/log.jsonl" ] && [ -n "$(tail -c 1 "$S/log.jsonl")" ]; then
    ae_gap=1
  fi
  # The last look at the lock, straight before the write (see "One writer
  # at a time", further down).
  if ! holds_lock; then
    LOCKED=0
    die "this write no longer holds the lock ($S/.lock): it was cleared while the write was under way. Nothing was added to log.jsonl. Run the same command again." 4
  fi
  if [ "$ae_gap" -eq 1 ]; then
    printf '\n' >> "$S/log.jsonl" || die "cannot write log.jsonl" 4
  fi
  printf '%s,"hash":"%s"}\n' "$ae_body" "$ENTRY_HASH" >> "$S/log.jsonl" || die "cannot write log.jsonl" 4
  ENTRY_TS=$ae_ts
}

# The hash of the entry just written and, on its own line, the entry's time.
print_entry() {
  printf 'Log entry: %s\n' "$ENTRY_HASH"
  printf 'Entry time (UTC): %s\n' "$ENTRY_TS"
}

append_lineage() {
  refuse_symlink "$S/lineage.jsonl"
  if [ -s "$S/lineage.jsonl" ] && [ -n "$(tail -c 1 "$S/lineage.jsonl")" ]; then
    printf '\n' >> "$S/lineage.jsonl" || die "cannot write lineage.jsonl" 4
  fi
  printf '%s\n' "$1" >> "$S/lineage.jsonl" || die "cannot write lineage.jsonl" 4
}

# One writer at a time. The lock is the folder .lock, which holds the
# writer's process id in the file pid.
#
# Taking the lock is two steps: make the folder, then create the file pid
# in it, and that file is created only if it is not there yet (set -C).
# The writer whose pid file it is holds the lock, and nobody else. Both
# steps are done by this shell itself, with no other process started in
# between, so a live writer's folder is without its pid file for a moment
# only. Giving the lock back is two steps as well, in the other order:
# remove pid (only if it still holds this writer's id), then the folder.
#
# Two writers can only both hold the lock if a pid file is taken away
# from a writer that is still writing. One place takes a pid file away
# from another process: clear_stale, below. Everything that follows is
# there to keep it from doing that to a writer that is alive.
#
# A lock left by a writer that was killed is cleared, so that a killed
# process cannot stop a stand-down from being recorded. It is cleared
# only when all of this holds:
#   - the waiter has found the same process id in the lock on every look
#     for two seconds. A writer holds the lock for well under a second
#     as a rule (about 0.4 s under Git Bash), so "kill -0" is not the
#     only thing between a live writer and a waiter. That matters where
#     kill -0 cannot be trusted to see the writer: a process of another
#     user, or one running under another Unix layer on the same folder
#     (Git Bash sees the processes of its own runtime only, not those of
#     WSL or of a second MSYS or Cygwin installation; a container does
#     not see its host's).
#   - kill -0 says no process has that id. A process id that was given
#     to some other program since counts as running: the lock then stays
#     and the write fails with a message, which is the safe way round.
#   - the waiter has made the folder .lock-clear, so that one waiter
#     clears at a time. Without that, two waiters could each clear "the"
#     stale lock, the second one clearing the lock the first had just
#     taken.
#   - inside .lock-clear, kill -0 is asked again and the pid file is read
#     after that, in this order. A process that is gone stays gone, and
#     while .lock-clear is held nobody else removes a pid file, so a file
#     that still names the dead process is the dead process's own.
#
# A lock folder with no pid file in it on every look for two seconds was
# left by a writer killed between the two steps, or by one that could
# not write its id. It is cleared the same way, and that needs no trust
# in anything: removing an empty folder takes the lock from nobody. A
# writer that was in fact alive and stopped for two seconds between its
# two steps finds its folder gone, or finds the pid file of the writer
# that came next, cannot create its own, and goes back to waiting.
#
# As a last check a writer reads the pid file once more just before it
# appends to the log, and stops without writing if the id in it is not
# its own.
#
# How long a writer waits, by the clock:
#   - a stand-down, the note of a compaction and a name chosen at
#     session start (name --auto): 3 seconds, because their hooks have
#     10 in all;
#   - any other write: for as long as the lock keeps changing hands, up
#     to 90 seconds, so that a dozen writers on a slow machine all get
#     their turn; it gives up sooner, after 20 seconds, when one and the
#     same process has held the lock all that time.
# A writer that gives up writes nothing, says so on standard error and
# exits 4.
#
# The wait is measured on the clock, not counted in sleeps: counting is
# not enough where starting a process is slow (under Git Bash a wait
# counted as 3 seconds took 4 as a rule). The clock is read once per turn
# of the loop and only while waiting, so a write that finds the lock free
# costs nothing more. It has whole seconds, so "3 seconds" ends between 2
# and 3 seconds after the wait began, plus at most one more turn of the
# loop. A waiter looks every 0.2 s or so for the first two seconds, and
# every 0.4 to 0.5 s after that unless it is a stand-down or the lock
# has no pid file: a dozen waiters that each start three processes five
# times a second slow the one writer down on a machine where starting a
# process is slow. For the same reason a waiter does not start mkdir
# while it can see that the folder is there.

# clock: seconds since midnight UTC in CLOCK, from the hour, minute and
# second (plain POSIX date).
clock() {
  ck_now=$(date -u '+%H:%M:%S')
  ck_h=${ck_now%%:*}
  ck_s=${ck_now##*:}
  ck_m=${ck_now#*:}
  ck_m=${ck_m%%:*}
  CLOCK=$((${ck_h#0} * 3600 + ${ck_m#0} * 60 + ${ck_s#0}))
}

# since <earlier CLOCK>: seconds from then to the last reading of the
# clock, in SINCE. A wait that crosses midnight is counted across it.
since() {
  SINCE=$((CLOCK - $1))
  [ "$SINCE" -ge 0 ] || SINCE=$((SINCE + 86400))
}

# lock_pid: the process id in the lock's pid file, in LOCK_PID. Empty
# when there is no such file or it does not hold a number.
lock_pid() {
  LOCK_PID=
  if [ -f "$S/.lock/pid" ] && [ ! -L "$S/.lock/pid" ]; then
    read -r LOCK_PID < "$S/.lock/pid" || LOCK_PID=
  fi
  case $LOCK_PID in
    *[!0-9]*) LOCK_PID= ;;
  esac
}

# clear_stale <process id, or "" for a lock without one>: see above.
# What it cleared is said on standard error.
clear_stale() {
  [ -L "$S/.lock-clear" ] && return 0
  mkdir "$S/.lock-clear" 2> /dev/null || return 0
  cs_ok=1
  [ -L "$S/.lock" ] && cs_ok=0
  if [ "$cs_ok" -eq 1 ] && [ -z "$1" ]; then
    # No process id was seen. Look twice more, a moment apart.
    if [ -e "$S/.lock/pid" ] || [ -L "$S/.lock/pid" ]; then
      cs_ok=0
    else
      sleep 0.2 2> /dev/null || sleep 1
      if [ -e "$S/.lock/pid" ] || [ -L "$S/.lock/pid" ] || [ ! -d "$S/.lock" ]; then
        cs_ok=0
      fi
    fi
    if [ "$cs_ok" -eq 1 ] && rmdir "$S/.lock" 2> /dev/null; then
      printf 'succession: cleared a lock that held no process id for two seconds (%s).\n' "$S/.lock" >&2
    fi
  elif [ "$cs_ok" -eq 1 ]; then
    # First: is the process gone? Then: is the pid file still its own?
    if kill -0 "$1" 2> /dev/null; then
      cs_ok=0
    else
      lock_pid
      [ "$LOCK_PID" = "$1" ] || cs_ok=0
    fi
    if [ "$cs_ok" -eq 1 ]; then
      rm -f "$S/.lock/pid"
      rmdir "$S/.lock" 2> /dev/null
      printf 'succession: cleared a lock left by process %s, which is no longer running (%s).\n' "$1" "$S/.lock" >&2
    fi
  fi
  rmdir "$S/.lock-clear" 2> /dev/null
  return 0
}

# take_lock: makes the folder and creates pid in it. Returns 0 when this
# process holds the lock. mkdir is not started while the folder is seen
# to be there. (A redirection that fails on printf does not end the
# shell: printf is not one of the special built-ins.)
take_lock() {
  if [ -d "$S/.lock" ] || [ -L "$S/.lock" ]; then
    return 1
  fi
  mkdir "$S/.lock" 2> /dev/null || return 1
  set -C
  { printf '%s\n' "$$" > "$S/.lock/pid"; } 2> /dev/null
  tl_rc=$?
  set +C
  [ "$tl_rc" -eq 0 ] || return 1
  LOCKED=1
  return 0
}

# holds_lock: the pid file names this process.
holds_lock() {
  lock_pid
  [ "$LOCK_PID" = "$$" ]
}

# unlock: gives the lock back, if this process holds it. A pid file that
# names another process is left alone.
LOCKED=0
unlock() {
  [ "$LOCKED" -eq 1 ] || return 0
  LOCKED=0
  holds_lock || return 0
  rm -f "$S/.lock/pid"
  rmdir "$S/.lock" 2> /dev/null
  return 0
}

# lock_busy <seconds waited>: the message of a writer that gives up.
lock_busy() {
  lb_who="The lock folder has no process id in it."
  if [ ! -d "$S/.lock" ]; then
    if [ -e "$S/.lock" ] || [ -L "$S/.lock" ]; then
      die "something that is not a folder is in the way of the lock: $S/.lock. Nothing was written. Remove it by hand." 4
    fi
    die "the lock folder $S/.lock could not be made in $1 s, and nothing is in its place. Is $S writable? Nothing was written." 4
  fi
  if [ -n "$lk_pid" ]; then
    if kill -0 "$lk_pid" 2> /dev/null; then
      lb_who="The lock names process $lk_pid, which is running."
    else
      lb_who="The lock names process $lk_pid, which this shell does not see running."
    fi
  fi
  die "another Succession write is still in progress (lock: $S/.lock). Waited $1 s. $lb_who Nothing was written. If no other session is running, remove that folder, and $S/.lock-clear if it is there." 4
}

lock() {
  lk_limit=90
  lk_same=20
  lk_short=0
  if [ "$event" = stand_down ] || [ "$event" = compact ] || [ "$event:${1-}" = name:--auto ]; then
    lk_short=1
    lk_limit=3
    lk_same=3
  fi
  lk_start=
  lk_seen=
  lk_since=
  # The last digit of this process's id makes its pauses a little longer
  # than the next waiter's, so that waiters started together do not all
  # look at the same moments.
  lk_odd=$(($$ % 10))
  trap 'unlock' EXIT
  trap 'exit 1' INT TERM HUP
  while :; do
    refuse_symlink "$S/.lock"
    if take_lock; then
      break
    fi
    clock
    [ -n "$lk_start" ] || lk_start=$CLOCK
    # What is in the way: a process id, a folder without one, or nothing
    # (the lock was given back just now, or the folder cannot be made).
    lock_pid
    lk_pid=$LOCK_PID
    if [ -n "$lk_pid" ]; then
      lk_now="pid $lk_pid"
    elif [ -d "$S/.lock" ]; then
      lk_now=empty
    else
      lk_now=none
    fi
    if [ "$lk_now" != "$lk_seen" ]; then
      lk_seen=$lk_now
      lk_since=$CLOCK
    fi
    since "$lk_since"
    lk_age=$SINCE
    if [ "$lk_age" -ge 2 ]; then
      case $lk_now in
        empty)
          clear_stale ""
          if take_lock; then
            break
          fi
          ;;
        pid*)
          if ! kill -0 "$lk_pid" 2> /dev/null; then
            clear_stale "$lk_pid"
            # Try again at once: if the lock was cleared, it is free now.
            if take_lock; then
              break
            fi
          fi
          ;;
      esac
    fi
    since "$lk_start"
    if [ "$SINCE" -ge "$lk_limit" ]; then
      lock_busy "$SINCE"
    fi
    lk_nap=0.2$lk_odd
    case $lk_now in
      none)
        # Nothing is in the way, and still the folder cannot be made.
        [ "$lk_age" -lt 5 ] || lock_busy "$SINCE"
        ;;
      empty)
        [ "$lk_age" -lt "$lk_same" ] || lock_busy "$SINCE"
        ;;
      *)
        [ "$lk_age" -lt "$lk_same" ] || lock_busy "$SINCE"
        if [ "$SINCE" -ge 2 ] && [ "$lk_short" -eq 0 ]; then
          lk_nap=0.4$lk_odd
        fi
        ;;
    esac
    sleep "$lk_nap" 2> /dev/null || sleep 1
  done
}

require_seat_file() {
  read_seat
  case $? in
    0) ;;
    1) die "no officeholder is seated in this project" 5 ;;
    3) die "$SEAT_CODENAME is seated by name alone, so there is no tenure to record this in. /succession:seat turns handoffs on and keeps the name." 5 ;;
    *) die "seat.json cannot be read. Compare it with lineage.jsonl and repair it by hand." 4 ;;
  esac
}

cmd_seat() {
  [ $# -eq 1 ] || usage
  code=$1
  case $code in
    '' | *[!A-Za-z0-9-]* | *-) die "a codename is letters, digits and hyphens, starting with a letter (got: $code)" 2 ;;
    [A-Za-z]*) ;;
    *) die "a codename starts with a letter (got: $code)" 2 ;;
  esac
  [ "${#code}" -le 32 ] || die "a codename is at most 32 characters" 2

  read_seat
  case $? in
    0 | 1) ;;
    # A seat by name alone is replaced by this one: handoffs are turned on.
    3) SEAT_CODENAME= ;;
    *) die "seat.json cannot be read. Compare it with lineage.jsonl and repair it by hand." 4 ;;
  esac
  case $SEAT_STATUS in
    occupied)
      die "the seat is occupied by $SEAT_CODENAME-$SEAT_ORDINAL. Close that tenure before seating a successor." 5
      ;;
    stood_down)
      die "$SEAT_CODENAME-$SEAT_ORDINAL was stood down and has not closed. Close it, or record that it left no handoff: log-append.sh vacate \"<reason>\"" 5
      ;;
  esac

  # A previous handoff must have been through verify.sh before the seat
  # can be claimed. A failed claim does not block; an unchecked handoff does.
  last_closed
  note="No predecessor."
  if [ -n "$LC_TENURE" ]; then
    note="Predecessor $LC_TENURE left no handoff."
    refuse_symlink "$S/tenures/$LC_TENURE"
    refuse_symlink "$S/tenures/$LC_TENURE/handoff.md"
    if [ -s "$S/tenures/$LC_TENURE/handoff.md" ]; then
      verdict=
      if [ -f "$S/log.jsonl" ]; then
        verdict=$(grep -F "\"type\":\"verify\",\"tenure\":\"$LC_TENURE\"" "$S/log.jsonl" | tail -n 1)
      fi
      verdict=${verdict%"$CR"}
      if [ -z "$verdict" ]; then
        die "the handoff of $LC_TENURE has not been verified. Run verify.sh, show its output to the owner, then seat." 6
      fi
      verdict=${verdict#*,\"data\":\"}
      verdict=${verdict%%\",\"prev\":\"*}
      note="Predecessor $LC_TENURE: $verdict"
    fi
  fi

  seat_differs
  max_ordinal
  # The tenure folders show a tenure that seat.json does not know about.
  # That is what is left when git puts older state files back (git stash,
  # git checkout, git reset --hard): they take seat.json, the log and
  # the lineage back, and leave a folder that was never committed.
  behind=
  to_int "${SEAT_ORDINAL:-0}"
  if [ "$MAX_DIR_ORD" -gt "$TI" ]; then
    behind=$MAX_DIR
  fi
  ord=$(printf '%03d' $((MAX_ORD + 1)))
  lower=$(printf '%s' "$code" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
  tenure="$ord-$lower"
  ts=$(now_utc)

  # The tenure folder is always a new one: its number is above every
  # folder that is there. A folder or link already at that path is not
  # used.
  refuse_symlink "$S/tenures/$tenure"
  mkdir "$S/tenures/$tenure" 2> /dev/null || die "cannot create a new folder at $S/tenures/$tenure (something is already there)" 4
  printf '# Checkpoints - %s-%s\n' "$code" "$ord" > "$S/tenures/$tenure/checkpoints.md" || die "cannot write checkpoints.md" 4

  append_entry seat "$tenure" "$code-$ord seated. $note"
  append_lineage '{"ordinal":"'"$ord"'","codename":"'"$code"'","tenure":"'"$tenure"'","event":"seated","ts":"'"$ts"'","entry":"'"$ENTRY_HASH"'"}'
  write_seat occupied "$ord" "$code" "$tenure" "$ts" "$ts"

  printf 'Seated: %s-%s (tenure folder .succession/tenures/%s).\n' "$code" "$ord" "$tenure"
  print_entry
  printf 'Owner stop phrase: Stand down, %s\n' "$code"
  if [ ! -s "$S/charter.md" ]; then
    printf 'Note: .succession/charter.md is missing. Write it with the owner before working.\n'
  fi
  if [ -n "$DIFFERS" ]; then
    printf 'WARNING: before this seating, seat.json and the log disagreed: %s. One of the two was probably put back to an older version (git stash, git checkout and git reset --hard do that to tracked files) or edited by hand. A seating, a stand-down or a close may be missing from the record. Tell the owner now; "git stash list" and "git reflog" are where to look for the newer files.\n' "$DIFFERS"
  fi
  if [ -n "$behind" ]; then
    printf 'WARNING: the folder .succession/tenures/%s is there, but seat.json and the log do not show that tenure. The state files were probably put back to an older version: git stash, git checkout and git reset --hard do that to tracked files. A seating, a checkpoint or a stand-down may be missing from the record. Tell the owner now; "git stash list" and "git reflog" are where to look for the newer files.\n' "$behind"
  fi
}

# pick_name: a codename for "name --auto", in PICKED. The names are
# taken from .succession/names.md (one per line or separated by commas)
# when it is a plain file, otherwise from the default theme of
# name-themes.md. Anything that is not a valid codename is passed over.
# Which one is picked depends on the repository's path alone.
pick_name() {
  PICKED=
  pn_src="$S/names.md"
  pn_all=1
  if [ ! -f "$pn_src" ] || [ -L "$pn_src" ]; then
    pn_src="$here/../skills/_shared/name-themes.md"
    pn_all=0
  fi
  pn_list=
  pn_n=0
  pn_in=$pn_all
  if [ -f "$pn_src" ]; then
    while IFS= read -r pn_line || [ -n "$pn_line" ]; do
      pn_line=${pn_line%"$CR"}
      if [ "$pn_all" -eq 0 ]; then
        case $pn_line in
          '## Default theme'*) pn_in=1; continue ;;
          '#'*) pn_in=0; continue ;;
        esac
      fi
      [ "$pn_in" -eq 1 ] || continue
      pn_rest=$pn_line,
      while [ -n "$pn_rest" ]; do
        pn_word=${pn_rest%%,*}
        pn_rest=${pn_rest#*,}
        pn_word=${pn_word#"${pn_word%%[! ]*}"}
        pn_word=${pn_word%"${pn_word##*[! ]}"}
        valid_code "$pn_word" || continue
        pn_list="$pn_list $pn_word"
        pn_n=$((pn_n + 1))
      done
    done < "$pn_src"
  fi
  if [ "$pn_n" -eq 0 ]; then
    PICKED=Sextant
    return 0
  fi
  pn_sum=$(printf '%s' "$root" | cksum)
  pn_sum=${pn_sum%% *}
  case $pn_sum in
    '' | *[!0-9]*) pn_sum=0 ;;
  esac
  pn_i=$((pn_sum % pn_n))
  for pn_word in $pn_list; do
    if [ "$pn_i" -eq 0 ]; then
      PICKED=$pn_word
      return 0
    fi
    pn_i=$((pn_i - 1))
  done
  PICKED=Sextant
}

# A seat by name alone. Writes seat.json and nothing else.
cmd_name() {
  [ $# -eq 1 ] || usage
  code=$1
  auto=0
  if [ "$code" = --auto ]; then
    # Only a project with nothing of Succession in it is named this way.
    for na_f in seat.json log.jsonl lineage.jsonl charter.md; do
      if [ -e "$S/$na_f" ] || [ -L "$S/$na_f" ]; then
        return 0
      fi
    done
    pick_name
    code=$PICKED
    auto=1
  fi
  valid_code "$code" || die "a codename is letters, digits and hyphens, starting with a letter, at most 32 characters (got: $code)" 2
  read_seat
  case $? in
    1 | 3) ;;
    *) die "this project already keeps handoffs (see .succession/seat.json). A seat by name alone is for a project that has none." 5 ;;
  esac
  if [ -s "$S/log.jsonl" ] || [ -s "$S/lineage.jsonl" ]; then
    die "this project already keeps handoffs (see .succession/log.jsonl). A seat by name alone is for a project that has none." 5
  fi
  ts=$(now_utc)
  ws_tmp="$S/seat.json.tmp"
  fresh_file "$ws_tmp"
  {
    printf '{\n'
    printf '  "mode": "name",\n'
    printf '  "codename": "%s",\n' "$code"
    printf '  "updated": "%s"\n' "$ts"
    printf '}\n'
  } > "$ws_tmp" || die "cannot write $ws_tmp" 4
  mv -f "$ws_tmp" "$S/seat.json" || die "cannot write seat.json" 4
  [ "$auto" -eq 0 ] || return 0
  printf 'Named: %s. Nothing else is kept: no log, no checkpoints, no handoffs.\n' "$code"
  printf 'Handoffs are off. To turn them on and keep the name %s, send /succession:seat.\n' "$code"
}

cmd_charter() {
  [ $# -eq 0 ] || usage
  refuse_symlink "$S/charter.md"
  if [ -e "$S/charter.md" ]; then
    printf 'The charter is already there and was left as it is: .succession/charter.md\n'
    return 0
  fi
  ch_template="$here/../skills/_shared/charter-template.md"
  [ -f "$ch_template" ] || die "the charter template is missing from the plugin: $ch_template" 4
  fresh_file "$S/charter.md.tmp"
  cat "$ch_template" > "$S/charter.md.tmp" || die "cannot write the charter" 4
  mv -f "$S/charter.md.tmp" "$S/charter.md" || die "cannot write the charter" 4
  printf 'Charter written from the template: .succession/charter.md\n'
}

# The last line of a close: where .succession/ stands in git, and the
# command line that commits it. "git status" and "git check-ignore" are
# asked; nothing is staged, committed or changed here, and git is told
# not to refresh its index file while it looks (--no-optional-locks).
#
# The command line is written for the owner to paste, in the project's
# top folder. Its two halves are joined with ";" and not "&&" because
# Windows PowerShell 5.1 does not know "&&". The path after "--" keeps
# the commit to .succession/, whatever else the owner has staged.
git_line() {
  gl_changes=$(git --no-optional-locks -C "$root" status --porcelain --untracked-files=normal -- .succession 2> /dev/null)
  if [ -n "$gl_changes" ]; then
    printf 'Git: the state files in .succession/ are not committed yet. To commit them: git add .succession; git commit -m "Succession: %s closed" -- .succession\n' "$1"
  elif git -C "$root" check-ignore -q .succession 2> /dev/null; then
    printf 'Git: .succession/ is ignored by git in this project, so there is nothing to commit.\n'
  else
    printf 'Git: nothing in .succession/ is waiting to be committed.\n'
  fi
}

cmd_checkpoint() {
  [ $# -eq 1 ] || usage
  [ -n "$1" ] || die "a checkpoint needs a one-line summary" 2
  require_seat_file
  [ "$SEAT_STATUS" = occupied ] || die "no officeholder is seated (seat status: $SEAT_STATUS)" 5
  text=$(json_text "$1" "the summary") || exit 2
  append_entry checkpoint "$SEAT_TENURE" "$text"
  printf 'Checkpoint logged for %s-%s.\n' "$SEAT_CODENAME" "$SEAT_ORDINAL"
  print_entry
  printf 'Cite it in checkpoints.md as: CLAIM [log:%s] <what this checkpoint records>\n' "$ENTRY_HASH"
}

# end_tenure <how> <escaped summary> <escaped last words> [<handoff sha256>]
end_tenure() {
  ts=$(now_utc)
  how=$1
  if [ "$how" = close ] && [ "$SEAT_STATUS" = stood_down ]; then
    how=stand_down
  fi
  data="$SEAT_CODENAME-$SEAT_ORDINAL left the seat ($how)."
  if [ -n "${4-}" ]; then
    data="$data Handoff sha256 $4."
  fi
  data="$data $2"
  if [ -n "$3" ]; then
    data="$data Last words: $3"
  fi
  append_entry "$1" "$SEAT_TENURE" "$data"
  append_lineage '{"ordinal":"'"$SEAT_ORDINAL"'","codename":"'"$SEAT_CODENAME"'","tenure":"'"$SEAT_TENURE"'","event":"closed","ts":"'"$ts"'","how":"'"$how"'","summary":"'"$2"'","last_words":"'"$3"'","entry":"'"$ENTRY_HASH"'"}'
  write_seat vacant "$SEAT_ORDINAL" "$SEAT_CODENAME" "$SEAT_TENURE" "$SEAT_SEATED" "$ts"
}

cmd_close() {
  if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    usage
  fi
  [ -n "$1" ] || die "close needs a one-line summary of the tenure" 2
  require_seat_file
  case $SEAT_STATUS in
    occupied | stood_down) ;;
    *) die "no officeholder is seated (seat status: $SEAT_STATUS)" 5 ;;
  esac
  refuse_symlink "$S/tenures/$SEAT_TENURE"
  refuse_symlink "$S/tenures/$SEAT_TENURE/handoff.md"
  [ -s "$S/tenures/$SEAT_TENURE/handoff.md" ] || die "write the handoff first: .succession/tenures/$SEAT_TENURE/handoff.md is missing or empty" 5
  summary=$(json_text "$1" "the summary") || exit 2
  words=$(json_text "${2-}" "the last words") || exit 2
  # The handoff is final now. Its hash goes into the close entry, so that
  # a change made to it afterwards shows.
  hsum=$(tr -d '\r' < "$S/tenures/$SEAT_TENURE/handoff.md" | sha256_stdin) || die "no sha256 tool found (need sha256sum or shasum)" 4
  [ "${#hsum}" -eq 64 ] || die "sha256 tool gave an unexpected answer" 4
  end_tenure close "$summary" "$words" "$hsum"
  printf 'Tenure closed: %s-%s. The seat is vacant.\n' "$SEAT_CODENAME" "$SEAT_ORDINAL"
  print_entry
  printf 'Handoff: .succession/tenures/%s/handoff.md\n' "$SEAT_TENURE"
  printf 'Handoff sha256, recorded in the log: %s\n' "$hsum"
  # Everything is written. The lock is given back before git is asked,
  # which can take a while in a large project.
  unlock
  git_line "$SEAT_CODENAME-$SEAT_ORDINAL"
}

cmd_vacate() {
  [ $# -eq 1 ] || usage
  [ -n "$1" ] || die "vacate needs a reason" 2
  require_seat_file
  case $SEAT_STATUS in
    occupied | stood_down) ;;
    *) die "no officeholder is seated (seat status: $SEAT_STATUS)" 5 ;;
  esac
  reason=$(json_text "$1" "the reason") || exit 2
  end_tenure vacate "$reason" ""
  printf 'Seat vacated without a handoff: %s-%s.\n' "$SEAT_CODENAME" "$SEAT_ORDINAL"
  print_entry
}

cmd_stand_down() {
  [ $# -eq 0 ] || usage
  require_seat_file
  case $SEAT_STATUS in
    occupied)
      append_entry stand_down "$SEAT_TENURE" "The owner stood down $SEAT_CODENAME-$SEAT_ORDINAL."
      write_seat stood_down "$SEAT_ORDINAL" "$SEAT_CODENAME" "$SEAT_TENURE" "$SEAT_SEATED" "$(now_utc)"
      # A second witness, as a new file in the tenure folder. Git leaves a
      # file it does not track alone, so this one is still there if the
      # state files are put back to an older version.
      if [ -d "$S/tenures/$SEAT_TENURE" ] && [ ! -L "$S/tenures/$SEAT_TENURE" ]; then
        fresh_file "$S/tenures/$SEAT_TENURE/stood-down"
        printf 'The owner stood down %s-%s at %s. Log entry %s.\n' "$SEAT_CODENAME" "$SEAT_ORDINAL" "$ENTRY_TS" "$ENTRY_HASH" > "$S/tenures/$SEAT_TENURE/stood-down"
      fi
      printf 'Stand-down recorded for %s-%s.\n' "$SEAT_CODENAME" "$SEAT_ORDINAL"
      print_entry
      ;;
    stood_down)
      printf 'Stand-down already recorded for %s-%s.\n' "$SEAT_CODENAME" "$SEAT_ORDINAL"
      ;;
    *)
      die "no officeholder is seated (seat status: $SEAT_STATUS)" 5
      ;;
  esac
}

# The text is fixed, and session-start.sh knows it by heart: an entry
# with this text is the plugin's note, not a checkpoint of the
# officeholder's.
cmd_compact() {
  [ $# -eq 1 ] || usage
  case $1 in
    manual | auto) ;;
    *) usage ;;
  esac
  require_seat_file
  [ "$SEAT_STATUS" = occupied ] || die "no officeholder is seated (seat status: $SEAT_STATUS)" 5
  append_entry checkpoint "$SEAT_TENURE" "Context compacted ($1). Written by the plugin before Claude Code compacted the context, not by the officeholder."
  printf 'Compaction noted for %s-%s.\n' "$SEAT_CODENAME" "$SEAT_ORDINAL"
  print_entry
}

cmd_verify() {
  [ $# -eq 2 ] || usage
  is_tenure_name "$1" || die "not a tenure name: $1" 2
  [ -d "$S/tenures/$1" ] || die "no such tenure: $1" 2
  text=$(json_text "$2" "the verdict") || exit 2
  append_entry verify "$1" "$text"
  printf 'Verdict recorded. Log entry: %s\n' "$ENTRY_HASH"
}

[ $# -ge 1 ] || usage
event=$1
shift

command -v git >/dev/null 2>&1 || die "git was not found. Succession needs git." 3
root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$root" ]; then
  why=$(git rev-parse --show-toplevel 2>&1 | head -n 1)
  die "Succession needs a git repository. Run 'git init' here, or open a project that has one, and try again. (git said: $why)" 3
fi
S="$root/.succession"
here=${0%/*}
[ "$here" != "$0" ] || here=.

case $event in
  charter | name | seat | checkpoint | close | vacate | stand_down | compact | verify) ;;
  *) usage ;;
esac

refuse_symlink "$S"
if [ "$event" = name ]; then
  mkdir -p "$S" || die "cannot create $S" 4
fi
if [ "$event" = seat ] || [ "$event" = charter ]; then
  mkdir -p "$S" || die "cannot create $S" 4
  refuse_symlink "$S/tenures"
  mkdir -p "$S/tenures" || die "cannot create $S" 4
fi
[ -d "$S" ] || die "this project has no .succession folder yet. The seat skill creates it." 5
refuse_symlink "$S/tenures"
refuse_symlink "$S/seat.json"
refuse_symlink "$S/log.jsonl"
refuse_symlink "$S/lineage.jsonl"

lock "$@"
case $event in
  charter) cmd_charter "$@" ;;
  name) cmd_name "$@" ;;
  seat) cmd_seat "$@" ;;
  checkpoint) cmd_checkpoint "$@" ;;
  close) cmd_close "$@" ;;
  vacate) cmd_vacate "$@" ;;
  stand_down) cmd_stand_down "$@" ;;
  compact) cmd_compact "$@" ;;
  verify) cmd_verify "$@" ;;
esac
exit 0
