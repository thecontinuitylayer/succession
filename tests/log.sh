#!/bin/sh
# The hash-chained log (log-append.sh writes it, verify.sh walks it).
#
# Covers what the three-tenure run does not: several writers at once, a
# lock left behind by a killed writer, awkward text, and each kind of
# damage a hand can do to the file.

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

title "The log"
new_project log
printf 'x\n' > a.txt
commit_all "Initial commit" > /dev/null
quiet "$SH" "$SCRIPTS/log-append.sh" seat Sextant
log=.succession/log.jsonl
# The project's folder as git names it, which is how the scripts name it
# in a message. It is not always how this test got there: on macOS the
# temporary folder is reached through a link, and Git for Windows writes
# C:/... where the shell has /c/...
TOP=$(git rev-parse --show-toplevel)
check "seat: the entry's time is printed under its hash, and is the ts in the log" entry_time_ok "$OUT" "$log"

chain() {
  quiet "$SH" "$SCRIPTS/verify.sh" --draft --checkpoints
  CHAIN_LINE=$(printf '%s\n' "$OUT" | grep '^Log chain:')
}

# crowd <folder> <count> <text>: <count> checkpoint writers at once, and
# a wait until all of them are done. Each writer's exit code and what it
# wrote to standard error are kept in <folder>, so that a writer that
# gave up cannot go unnoticed. CROWD_PATH, when set, is the PATH the
# writers run with. CROWD_TOOK is how long it took, in whole seconds.
crowd() {
  cw_dir=$1
  mkdir -p "$cw_dir"
  cw_t0=$(date +%s)
  cw_i=1
  while [ "$cw_i" -le "$2" ]; do
    (
      PATH=${CROWD_PATH:-$PATH} "$SH" "$SCRIPTS/log-append.sh" checkpoint "$3 $cw_i" > /dev/null 2> "$cw_dir/err.$cw_i"
      echo "$?" > "$cw_dir/rc.$cw_i"
    ) &
    cw_i=$((cw_i + 1))
  done
  wait
  CROWD_TOOK=$(($(date +%s) - cw_t0))
}

# crowd_done <folder> <count>: every writer exited 0.
crowd_done() {
  cd_i=1
  while [ "$cd_i" -le "$2" ]; do
    cd_rc=
    [ -f "$1/rc.$cd_i" ] && read -r cd_rc < "$1/rc.$cd_i"
    [ "$cd_rc" = 0 ] || return 1
    cd_i=$((cd_i + 1))
  done
  return 0
}

# crowd_said <folder> <text>: how many of the writers said <text> on
# standard error.
crowd_said() {
  cat "$1"/err.* 2> /dev/null | grep -c -F "$2"
}

# twins: the numbers that more than one entry of the log carries, on one line.
twins() {
  sed 's/^{"seq":\([0-9]*\),.*/\1/' "$log" | sort -n | uniq -d | tr '\n' ' '
}

# crowd_report <folder> <count>: everything needed to tell, from the
# output alone, which way a crowd of writers went wrong: entries missing
# with the chain intact (writers gave up), or two entries with the same
# number (two writers held the lock at once). The lines start with
# "diag:" and autocrlf.sh repeats them.
crowd_report() {
  printf '      diag: %s writers were started and took %s s. The log has %s lines, %s of them checkpoints.\n' \
    "$2" "$CROWD_TOOK" "$(grep -c '' "$log")" "$(grep -c '"type":"checkpoint"' "$log")"
  printf '      diag: numbers carried by more than one entry: %s\n' "$(twins | grep . || echo none)"
  cr_i=1
  while [ "$cr_i" -le "$2" ]; do
    cr_rc='no exit code was written'
    [ -f "$1/rc.$cr_i" ] && read -r cr_rc < "$1/rc.$cr_i"
    printf '      diag: writer %s: exit %s; standard error: %s\n' "$cr_i" "$cr_rc" "$(tr '\n' ' ' < "$1/err.$cr_i" 2> /dev/null | cut -c 1-400)"
    cr_i=$((cr_i + 1))
  done
  for cr_left in .succession/.lock .succession/.lock/pid .succession/.lock-clear; do
    [ ! -e "$cr_left" ] || printf '      diag: left behind: %s\n' "$cr_left"
  done
  [ ! -f .succession/.lock/pid ] || printf '      diag: the lock names process %s\n' "$(cat .succession/.lock/pid)"
}

# crowd_checks <folder> <count>: the two things asked of every crowd, and
# the report when either fails. A writer that gave up says so and exits
# 4, so "every writer exited 0" is the check that no entry was dropped.
crowd_checks() {
  cc_fail=$FAIL
  check "every one of the $2 writers exited 0" crowd_done "$1" "$2"
  check "no two entries carry the same number" [ -z "$(twins)" ]
  [ "$FAIL" -eq "$cc_fail" ] || crowd_report "$1" "$2"
}

say "Twelve writers at once."
crowd "$WORK/twelve" 12 "parallel writer"
printf '      the twelve writers were done after %s s\n' "$CROWD_TOOK"
check "all twelve entries were written" [ "$(grep -c '"type":"checkpoint"' "$log")" -eq 12 ]
chain
printf '      %s\n' "$CHAIN_LINE"
check "the chain is intact (13 entries)" [ "$CHAIN_LINE" = "Log chain: intact (13 entries)." ]
check "no lock is left behind" [ ! -e .succession/.lock ]
crowd_checks "$WORK/twelve" 12
# Every one of these writers was alive for as long as it held the lock.
# A writer that says it cleared a lock left by a process took a live
# writer for a dead one.
printf '      locks cleared as left by a dead process: %s; as holding no process id: %s\n' \
  "$(crowd_said "$WORK/twelve" 'cleared a lock left by process')" "$(crowd_said "$WORK/twelve" 'cleared a lock that held no process id')"
check "no live writer was taken for a dead one" [ "$(crowd_said "$WORK/twelve" 'cleared a lock left by process')" -eq 0 ]
[ "$FAIL" -eq 0 ] || crowd_report "$WORK/twelve" 12
verdict "log parallel: $CHAIN_LINE"

say "Twelve writers at once on a slow machine: every tool the write starts takes a tenth of a second longer."
# Under Git Bash, starting a process costs 30 to 100 ms, and a write
# starts about ten. Twelve writers then need longer than the 12 seconds
# a writer used to wait, and the last ones gave up: entries were missing
# from a chain that was intact. The stand-ins below make that happen on
# any machine.
case $(uname -s 2> /dev/null) in
  MINGW* | MSYS* | CYGWIN*)
    printf '      not run here: on this system starting a process is that slow already, and the twelve writers above are this case.\n'
    ;;
  *)
    mkdir "$WORK/gitbash"
    for tool in date tail sha256sum shasum mkdir rm rmdir tr sed; do
      real_tool=$(command -v "$tool" 2> /dev/null) || continue
      case $real_tool in
        /*) ;;
        *) continue ;;
      esac
      printf '#!/bin/sh\nsleep 0.15 2> /dev/null || sleep 1\nexec "%s" "$@"\n' "$real_tool" > "$WORK/gitbash/$tool"
      chmod +x "$WORK/gitbash/$tool"
    done
    before=$(grep -c '' "$log")
    CROWD_PATH="$WORK/gitbash:$PATH"
    crowd "$WORK/slow-twelve" 12 "slow parallel writer"
    CROWD_PATH=
    printf '      the twelve slow writers were done after %s s\n' "$CROWD_TOOK"
    check "all twelve entries were written" [ "$(grep -c '' "$log")" -eq $((before + 12)) ]
    crowd_checks "$WORK/slow-twelve" 12
    check "no live writer was taken for a dead one" [ "$(crowd_said "$WORK/slow-twelve" 'cleared a lock left by process')" -eq 0 ]
    chain
    check "the chain is intact" [ "$CHAIN_LINE" = "Log chain: intact ($(grep -c '' "$log") entries)." ]
    check "no lock is left behind" absent .succession/.lock .succession/.lock-clear
    ;;
esac

say "A lock left behind by a writer that was killed."
mkdir .succession/.lock
sh -c 'echo $$' > .succession/.lock/pid
cat .succession/.lock/pid > "$WORK/stale.pid"
quiet "$SH" "$SCRIPTS/log-append.sh" checkpoint "after a stale lock"
check "the stale lock is cleared and the entry is written" [ "$RC" -eq 0 ]
check "the writer says that it cleared a lock, and whose" contains "$OUT" "succession: cleared a lock left by process $(cat "$WORK/stale.pid"), which is no longer running"
check "checkpoint: the entry's time is printed under its hash, and is the ts in the log" entry_time_ok "$OUT" "$log"
check "the line that says how to cite the entry is still the last one" contains "$(last_line "$OUT")" "Cite it in checkpoints.md as: CLAIM [log:$(entry_hash "$OUT")]"
check "no lock is left behind" [ ! -e .succession/.lock ]

say "Several writers behind a lock whose writer was killed: one clears it, the others wait."
# Two waiters used to be able to clear "the" stale lock one after the
# other, the second clearing the lock the first had just taken. Both then
# wrote, and two entries carried the same number: a chain broken for good.
round=1
race_ok=yes
while [ "$round" -le 4 ]; do
  before=$(grep -c '' "$log")
  mkdir .succession/.lock
  sh -c 'echo $$' > .succession/.lock/pid
  crowd "$WORK/stale-$round" 8 "behind a stale lock, round $round, writer"
  after=$(grep -c '' "$log")
  if [ "$after" -ne $((before + 8)) ] || ! crowd_done "$WORK/stale-$round" 8; then
    race_ok="round $round: $((after - before)) of 8 entries written"
    crowd_report "$WORK/stale-$round" 8
  fi
  round=$((round + 1))
done
check "four rounds of eight writers: every entry was written" [ "$race_ok" = yes ]
numbers=$(sed 's/^{"seq":\([0-9]*\),.*/\1/' "$log" | sort -n | uniq -d | grep -c '')
check "no two entries carry the same number" [ "$numbers" -eq 0 ]
chain
printf '      %s\n' "$CHAIN_LINE"
check "the chain is intact" [ "$CHAIN_LINE" = "Log chain: intact ($(grep -c '' "$log") entries)." ]
check "no lock is left behind" absent .succession/.lock .succession/.lock-clear
verdict "log stale lock race: $(printf '%s' "$CHAIN_LINE" | cut -c 1-17)"

say "Several writers behind a lock that holds no process id: it is cleared, and every writer writes once."
# The lock is the folder plus the file pid in it, created only if absent.
# A writer that loses its folder to the clearing, or finds another
# writer's pid file in it, goes back to waiting.
#
# In the second round a stand-in for mkdir waits half a second after it
# has made the lock folder. That is the moment between making the folder
# and writing the process id, held open: the waiters that are still
# counting from the abandoned lock then clear folders of writers that
# are alive. Before pid was created exclusively, two writers went on
# from there and their entries carried the same number.
real_mkdir=$(command -v mkdir)
mkdir "$WORK/slow"
cat > "$WORK/slow/mkdir" << EOF
#!/bin/sh
"$real_mkdir" "\$@" || exit \$?
case \$1 in
  */.succession/.lock) sleep 0.5 2> /dev/null || sleep 1 ;;
esac
exit 0
EOF
chmod +x "$WORK/slow/mkdir"
round=1
race_ok=yes
while [ "$round" -le 2 ]; do
  before=$(grep -c '' "$log")
  t0=$(date +%s)
  mkdir .succession/.lock
  if [ "$round" -eq 2 ]; then
    CROWD_PATH="$WORK/slow:$PATH"
    crowd "$WORK/abandoned-$round" 5 "behind an abandoned lock, slow mkdir, writer"
    CROWD_PATH=
  else
    crowd "$WORK/abandoned-$round" 5 "behind an abandoned lock, writer"
  fi
  printf '      round %s: the five writers were done after %s s\n' "$round" "$(($(date +%s) - t0))"
  after=$(grep -c '' "$log")
  if [ "$after" -ne $((before + 5)) ] || ! crowd_done "$WORK/abandoned-$round" 5; then
    race_ok="round $round: $((after - before)) of 5 entries written"
    crowd_report "$WORK/abandoned-$round" 5
  fi
  round=$((round + 1))
done
check "two rounds of five writers: every entry was written (${race_ok})" [ "$race_ok" = yes ]
numbers=$(sed 's/^{"seq":\([0-9]*\),.*/\1/' "$log" | sort -n | uniq -d | grep -c '')
check "no two entries carry the same number" [ "$numbers" -eq 0 ]
chain
check "the chain is intact" [ "$CHAIN_LINE" = "Log chain: intact ($(grep -c '' "$log") entries)." ]
check "no lock is left behind" absent .succession/.lock .succession/.lock-clear
verdict "log abandoned lock race: $(printf '%s' "$CHAIN_LINE" | cut -c 1-17)"

say "Two entries with the same number: the message says so."
cp "$log" "$WORK/log.before-twin"
# (The sed script sits in a variable: mksh and ksh, checking syntax with
# -n, misread a double quote inside single quotes inside "$(...)".)
twin_sed='s/writer [0-9]*"/the twin"/'
twin=$(tail -n 1 "$log" | sed "$twin_sed")
body=${twin%,\"hash\":\"*}
if command -v sha256sum > /dev/null 2>&1; then
  twinhash=$(printf '%s}' "$body" | sha256sum)
else
  twinhash=$(printf '%s}' "$body" | shasum -a 256)
fi
printf '%s,"hash":"%s"}\n' "$body" "${twinhash%% *}" >> "$log"
chain
printf '%s\n' "$OUT" | grep 'same number' | cut -c 1-160 | sed 's/^/      /'
check "reported BROKEN" contains "$CHAIN_LINE" "Log chain: BROKEN"
check "it says the two entries carry the same number" contains "$OUT" "it carries the same number as the entry before it"
check "it does not say 'entry N or N'" [ "$(printf '%s\n' "$OUT" | grep -c 'entry \([0-9]*\) or \1 ')" -eq 0 ]
cat "$WORK/log.before-twin" > "$log"

say "The stop phrase answers well inside the hook's 10 seconds, whatever the lock does."
# A lock folder with no process id in it: a writer killed at the wrong
# moment. It used to hold the stand-down for 12 seconds, past the timeout.
mkdir .succession/.lock
t0=$(date +%s)
HOOK=$(printf '%s' '{"hook_event_name":"UserPromptSubmit","prompt":"Stand down, Sextant"}' | CLAUDE_PROJECT_DIR="$PROJ" "$SH" "$SCRIPTS/stand-down.sh" 2>&1)
took=$(($(date +%s) - t0))
printf '      an abandoned lock with no process id: the hook answered in %s s\n' "$took"
check "the hook answered in under 8 seconds" [ "$took" -lt 8 ]
check "the abandoned lock was cleared and the stand-down recorded" grep -q '"status": "stood_down"' .succession/seat.json
check "the hook says it is recorded" contains "$HOOK" "The stand-down is recorded in .succession/log.jsonl"
check "no lock is left behind" absent .succession/.lock .succession/.lock-clear
# Back to an occupied seat for the cases below.
printf '# Handoff\n\n- CLAIM [none] nothing\n' > .succession/tenures/001-sextant/handoff.md
quiet "$SH" "$SCRIPTS/log-append.sh" close "Closed after the stand-down" "None."
quiet "$SH" "$SCRIPTS/verify.sh"
quiet "$SH" "$SCRIPTS/log-append.sh" seat Astrolabe
# A lock held by a process that is alive (this test). The stand-down
# cannot be written; the owner has to be told, in time.
mkdir .succession/.lock
printf '%s\n' "$$" > .succession/.lock/pid
t0=$(date +%s)
HOOK=$(printf '%s' '{"hook_event_name":"UserPromptSubmit","prompt":"Stand down, Astrolabe"}' | CLAUDE_PROJECT_DIR="$PROJ" "$SH" "$SCRIPTS/stand-down.sh" 2>&1)
took=$(($(date +%s) - t0))
printf '      a lock held by a live process: the hook answered in %s s\n' "$took"
check "the hook answered in under 8 seconds" [ "$took" -lt 8 ]
check "it says the stand-down could not be written" contains "$HOOK" "WARNING: the stand-down could not be written"
check "it has the officeholder stop all the same, and tell the owner" contains "$HOOK" "saying that the stand-down could not be recorded"
check "the owner is told directly too: the output is one JSON document with a systemMessage" \
  [ "$(printf '%s\n' "$HOOK" | grep -c '^{"systemMessage":"Succession: WARNING\. The stand-down of Astrolabe-002 could not be written[^"\\]*","hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"[^"\\]*"}}$')" -eq 1 ]
check "and it is a single line" [ "$(printf '%s\n' "$HOOK" | grep -c '')" -eq 1 ]
check "a live writer's lock was not cleared" [ -f .succession/.lock/pid ]
# The same, asked of the script the hook calls: what it says and how it exits.
before=$(grep -c '' "$log")
ERR=$("$SH" "$SCRIPTS/log-append.sh" stand_down 2>&1 > /dev/null)
RC=$?
printf '      %s\n' "$(printf '%s' "$ERR" | cut -c 1-200)"
check "a write that gives up exits 4" [ "$RC" -eq 4 ]
check "it says that another write holds the lock, and for how long it waited" contains "$ERR" "another Succession write is still in progress (lock: $TOP/.succession/.lock). Waited "
check "it names the process in the lock and says that it is running" contains "$ERR" "The lock names process $$, which is running."
check "it says that nothing was written" contains "$ERR" "Nothing was written."
check "and nothing was written" [ "$(grep -c '' "$log")" -eq "$before" ]
check "the lock is still the live writer's" [ "$(cat .succession/.lock/pid)" = "$$" ]
rm -f .succession/.lock/pid
rmdir .succession/.lock
HOOK=$(printf '%s' '{"hook_event_name":"UserPromptSubmit","prompt":"Stand down, Astrolabe"}' | CLAUDE_PROJECT_DIR="$PROJ" "$SH" "$SCRIPTS/stand-down.sh" 2>&1)
check "with the lock gone, the phrase is recorded" contains "$HOOK" "The stand-down is recorded"
check "a recorded stand-down is plain text, as before" [ "$(printf '%s' "$HOOK" | cut -c 1-12)" = "Succession: " ]
printf '# Handoff\n\n- CLAIM [none] nothing\n' > .succession/tenures/002-astrolabe/handoff.md
quiet "$SH" "$SCRIPTS/log-append.sh" close "Closed after the second stand-down" "None."
quiet "$SH" "$SCRIPTS/verify.sh"
quiet "$SH" "$SCRIPTS/log-append.sh" seat Compass

say "A lock held by a live process for longer than a writer used to wait."
# The cause of the entries missing on Windows, without the luck: a writer
# used to give up after 12 seconds, and what it said went unread. Now it
# waits for as long as the lock keeps changing hands, gives up after 20
# seconds behind one and the same live process, and says so.
#   0 s   this test takes the lock (its own process id: alive);
#         writer A starts
#   4 s   writer B starts
#  ~20 s  A gives up: exit 4, a message, nothing written
#         the test gives the lock back; B, 16 seconds in, writes
before=$(grep -c '' "$log")
mkdir .succession/.lock
printf '%s\n' "$$" > .succession/.lock/pid
t0=$(date +%s)
(
  "$SH" "$SCRIPTS/log-append.sh" checkpoint "writer A, behind a lock that stays held" > "$WORK/held-a.out" 2> "$WORK/held-a.err"
  echo "$?" > "$WORK/held-a.rc"
) &
pid_a=$!
sleep 4
t0_b=$(date +%s)
(
  "$SH" "$SCRIPTS/log-append.sh" checkpoint "writer B, behind a lock held for 16 seconds" > "$WORK/held-b.out" 2> "$WORK/held-b.err"
  echo "$?" > "$WORK/held-b.rc"
) &
pid_b=$!
wait "$pid_a"
took_a=$(($(date +%s) - t0))
waited_b=$(($(date +%s) - t0_b))
printf '      writer A gave up after %s s: %s\n' "$took_a" "$(cut -c 1-220 "$WORK/held-a.err")"
check "writer A waited at least 19 seconds, where a writer used to give up after 12" [ "$took_a" -ge 19 ]
check "and gave up before 30" [ "$took_a" -lt 30 ]
check "writer A exited 4" [ "$(cat "$WORK/held-a.rc")" = 4 ]
check "it said that another write holds the lock" contains "$(cat "$WORK/held-a.err")" "another Succession write is still in progress (lock: $TOP/.succession/.lock). Waited "
check "it named the process in the lock and said that it is running" contains "$(cat "$WORK/held-a.err")" "The lock names process $$, which is running."
check "it said that nothing was written, and printed nothing else" [ "$(grep -c 'Nothing was written\.' "$WORK/held-a.err")$(grep -c '' "$WORK/held-a.out")" = 10 ]
check "nothing was written while the lock was held" [ "$(grep -c '' "$log")" -eq "$before" ]
check "the live process's lock was not cleared" [ "$(cat .succession/.lock/pid 2> /dev/null)" = "$$" ]
check "writer B had been waiting for 13 seconds or more by then" [ "$waited_b" -ge 13 ]
rm -f .succession/.lock/pid
rmdir .succession/.lock
wait "$pid_b"
printf '      writer B wrote %s s after it started\n' "$(($(date +%s) - t0_b))"
check "writer B exited 0 once the lock was given back" [ "$(cat "$WORK/held-b.rc")" = 0 ]
check "its entry is the one entry added" [ "$(grep -c '' "$log")$(tail -n 1 "$log" | grep -c 'writer B, behind a lock held for 16 seconds')" = "$((before + 1))1" ]
[ "$FAIL" -eq 0 ] || printf '      diag: writer B: exit %s; standard error: %s\n' "$(cat "$WORK/held-b.rc")" "$(tr '\n' ' ' < "$WORK/held-b.err" | cut -c 1-400)"
chain
check "the chain is intact" [ "$CHAIN_LINE" = "Log chain: intact ($(grep -c '' "$log") entries)." ]
check "no lock is left behind" absent .succession/.lock .succession/.lock-clear

say "What kill -0 answers in the shell that runs the scripts: it is what the lock asks about a process id."
# A lock is never cleared while kill -0 says that its process is running.
# So the answer has to be "running" for a writer started by some other
# shell, under Git Bash as elsewhere.
# shellcheck disable=SC2016
# (SC2016, here and twice below: the dollar signs are for the shell that
# is started, not for this one.)
"$SH" -c 'echo "$$" > "$1"; sleep 4' sh "$WORK/alive.pid" &
pid_bg=$!
tries=0
while [ ! -s "$WORK/alive.pid" ] && [ "$tries" -lt 30 ]; do
  sleep 0.1 2> /dev/null || sleep 1
  tries=$((tries + 1))
done
alive=$(cat "$WORK/alive.pid")
printf '      a process started by another shell has the id %s\n' "$alive"
# shellcheck disable=SC2016
check "while it runs, kill -0 says that it is running" "$SH" -c 'kill -0 "$1" 2> /dev/null' sh "$alive"
wait "$pid_bg"
# shellcheck disable=SC2016
check "once it has ended, kill -0 says that it is not" "$SH" -c '! kill -0 "$1" 2> /dev/null' sh "$alive"

say "Writers that this shell cannot see running: the lock is not cleared while it keeps changing hands."
# "kill -0" answers for the processes this shell can see. It says "not
# running" of a writer that belongs to another user, and under Git Bash
# of one that runs under WSL or a second MSYS installation. Here eight
# such writers hold the lock one after the other, each for about a
# quarter of a second, each named by the id of a process that is gone.
# A waiter that went by kill -0 alone would clear the first of them at
# once and write next to it. A lock is cleared only when the same
# process id has been in it on every look for two seconds.
#
# The clock is read on both sides of each change. If two changes were
# two seconds apart by the clock, the machine stalled, a waiter may
# rightly have cleared the lock, and the case is run again.
gone=
count=0
while [ "$count" -lt 8 ]; do
  gone="$gone $(sh -c 'echo $$')"
  count=$((count + 1))
done
attempt=1
while [ "$attempt" -le 3 ]; do
  before=$(grep -c '' "$log")
  stalled=no
  robbed=no
  held_by=${gone##* }
  mkdir .succession/.lock
  printf '%s\n' "$held_by" > .succession/.lock/pid
  seen_a=$(date +%s)
  (
    "$SH" "$SCRIPTS/log-append.sh" checkpoint "behind writers that cannot be seen, attempt $attempt" > /dev/null 2> "$WORK/blind.err"
    echo "$?" > "$WORK/blind.rc"
  ) &
  pid_w=$!
  for next in $gone; do
    sleep 0.25 2> /dev/null || sleep 1
    [ "$(cat .succession/.lock/pid 2> /dev/null)" = "$held_by" ] || robbed=yes
    next_a=$(date +%s)
    [ -d .succession/.lock ] && printf '%s\n' "$next" > .succession/.lock/pid
    seen_b=$(date +%s)
    [ $((seen_b - seen_a)) -le 1 ] || stalled=yes
    seen_a=$next_a
    held_by=$next
  done
  [ "$(cat .succession/.lock/pid 2> /dev/null)" = "$held_by" ] || robbed=yes
  [ "$(grep -c '' "$log")" -eq "$before" ] || robbed=yes
  rm -f .succession/.lock/pid
  rmdir .succession/.lock 2> /dev/null
  [ $(($(date +%s) - seen_a)) -le 1 ] || stalled=yes
  wait "$pid_w"
  printf '      attempt %s: stalled=%s robbed=%s; the waiter exited %s and cleared %s locks\n' "$attempt" "$stalled" "$robbed" "$(cat "$WORK/blind.rc")" "$(grep -c 'cleared a lock' "$WORK/blind.err")"
  [ "$stalled" = yes ] || break
  # After a stall the lock may have been cleared and taken. It is free
  # again now: the waiter is done.
  attempt=$((attempt + 1))
done
check "the machine kept up in one of three attempts, so the case was put" [ "$stalled" = no ]
check "the lock was never taken from a writer that held it" [ "$robbed" = no ]
check "the waiter cleared nothing" [ "$(grep -c 'cleared a lock' "$WORK/blind.err")" -eq 0 ]
check "the waiter wrote once the last of them gave the lock back" [ "$(cat "$WORK/blind.rc")" = 0 ]
[ "$FAIL" -eq 0 ] || printf '      diag: the waiter said: %s\n' "$(tr '\n' ' ' < "$WORK/blind.err" | cut -c 1-400)"
chain
check "the chain is intact" [ "$CHAIN_LINE" = "Log chain: intact ($(grep -c '' "$log") entries)." ]
check "no lock is left behind" absent .succession/.lock .succession/.lock-clear

say "A writer whose lock is taken away while it writes stops before the log, and leaves the other writer's lock alone."
# The last look before the append. A stand-in for tail, which the write
# starts once it holds the lock, puts another process's id into the pid
# file: what the writer would find if its lock had been cleared and
# taken while it was held up.
real_tail=$(command -v tail)
mkdir "$WORK/thief"
cat > "$WORK/thief/tail" << EOF
#!/bin/sh
if [ -f "$PROJ/.succession/.lock/pid" ] && [ ! -e "$WORK/thief/done" ]; then
  : > "$WORK/thief/done"
  printf '%s\\n' "$$" > "$PROJ/.succession/.lock/pid"
fi
exec "$real_tail" "\$@"
EOF
chmod +x "$WORK/thief/tail"
before=$(grep -c '' "$log")
ERR=$(PATH="$WORK/thief:$PATH" "$SH" "$SCRIPTS/log-append.sh" checkpoint "from a writer that lost the lock" 2>&1 > /dev/null)
RC=$?
printf '      %s\n' "$(printf '%s' "$ERR" | cut -c 1-200)"
if [ -e "$WORK/thief/done" ]; then
  check "the writer exited 4" [ "$RC" -eq 4 ]
  check "it said that it no longer holds the lock and that nothing was added" contains "$ERR" "no longer holds the lock ($TOP/.succession/.lock): it was cleared while the write was under way. Nothing was added to log.jsonl."
  check "nothing was added to the log" [ "$(grep -c '' "$log")" -eq "$before" ]
  check "the other writer's lock is still there, with its process id" [ "$(cat .succession/.lock/pid 2> /dev/null)" = "$$" ]
  rm -f .succession/.lock/pid
  rmdir .succession/.lock
else
  # busybox sh runs its own tail and never looks for one on the PATH.
  printf '      not put here: this shell provides tail itself, so the stand-in was never started (the write exited %s).\n' "$RC"
fi
quiet "$SH" "$SCRIPTS/log-append.sh" checkpoint "after the writer that lost the lock"
check "the next write goes through" [ "$RC" -eq 0 ]

say "Something that is not a folder where the lock folder goes."
# The folder cannot be made, and no writer is there to wait for. The
# write says what is in the way after five seconds, not "another write
# is in progress" after ninety.
printf 'not a lock\n' > .succession/.lock
before=$(grep -c '' "$log")
t0=$(date +%s)
ERR=$("$SH" "$SCRIPTS/log-append.sh" checkpoint "with a file in the way of the lock" 2>&1 > /dev/null)
RC=$?
took=$(($(date +%s) - t0))
printf '      after %s s: %s\n' "$took" "$(printf '%s' "$ERR" | cut -c 1-200)"
check "the write exits 4, in under 15 seconds" [ "$RC$((took < 15))" = 41 ]
check "it says that something that is not a folder is in the way, and that nothing was written" contains "$ERR" "something that is not a folder is in the way of the lock: $TOP/.succession/.lock. Nothing was written."
check "nothing was added to the log" [ "$(grep -c '' "$log")" -eq "$before" ]
check "the file was left as it is" [ "$(cat .succession/.lock)" = "not a lock" ]
rm -f .succession/.lock

say "Awkward text in a summary."
quiet "$SH" "$SCRIPTS/log-append.sh" checkpoint 'Café ☕ "quoted" back\slash
second line	and a tab'
check "accepted" [ "$RC" -eq 0 ]
check "stored on one line, quote and backslash escaped" grep -q '"data":"Café ☕ \\"quoted\\" back\\\\slash second line and a tab"' "$log"
chain
check "the chain is intact" contains "$CHAIN_LINE" "Log chain: intact"
long=$(awk 'BEGIN { for (i = 0; i < 300; i++) printf "word "; }')
quiet "$SH" "$SCRIPTS/log-append.sh" checkpoint "$long"
check "a 1,500-byte summary is refused (exit 2)" [ "$RC" -eq 2 ]

say "A file that does not end with a line break."
cp "$log" "$WORK/log.good"
printf '%s' "$(cat "$log")" > "$log"
quiet "$SH" "$SCRIPTS/log-append.sh" checkpoint "after a missing line break"
chain
check "the next entry starts on its own line and the chain is intact" contains "$CHAIN_LINE" "Log chain: intact"

say "A log with CRLF line endings that ends with an empty line."
probe_check
cp "$log" "$WORK/log.lf"
entries=$(line_count "$log")
to_crlf "$log"
printf '\r\n' >> "$log"
check "every line of the log ends with CRLF, and the last line is empty" all_crlf "$log"
check "that is one line more than there are entries" [ "$(line_count "$log")" -eq $((entries + 1)) ]
quiet "$SH" "$SCRIPTS/log-append.sh" checkpoint "after an empty CRLF line"
check "the next entry takes the next number ($((entries + 1)))" grep -q "^{\"seq\":$((entries + 1)),.*after an empty CRLF line" "$log"
chain
printf '      %s\n' "$CHAIN_LINE"
check "and the chain is intact" [ "$CHAIN_LINE" = "Log chain: intact ($((entries + 1)) entries)." ]
verdict "log crlf, empty last line: $CHAIN_LINE"
cat "$WORK/log.lf" > "$log"

cp "$log" "$WORK/log.good"
total=$(grep -c '' "$log")

say "Damage: one entry edited."
sed '5s/parallel writer/PARALLEL WRITER/' "$WORK/log.good" > "$log"
chain
printf '      %s\n' "$CHAIN_LINE"
check "names entry 5" contains "$CHAIN_LINE" "BROKEN at entry 5 (line 5)"
check "one problem found" contains "$CHAIN_LINE" "Problems found: 1,"
verdict "log edited: $CHAIN_LINE rc=$RC"

say "Damage: one entry removed from the middle."
sed '5d' "$WORK/log.good" > "$log"
chain
printf '      %s\n' "$CHAIN_LINE"
check "names the entry after the gap (entry 6, now line 5)" contains "$CHAIN_LINE" "BROKEN at entry 6 (line 5)"
check "says what that means" contains "$OUT" "an entry between them was removed"
verdict "log removed: $CHAIN_LINE rc=$RC"

say "Damage: two entries swapped."
awk 'NR == 5 { held = $0; next } NR == 6 { print; print held; next } { print }' "$WORK/log.good" > "$log"
chain
printf '      %s\n' "$CHAIN_LINE"
check "reported BROKEN" contains "$CHAIN_LINE" "Log chain: BROKEN at entry 6 (line 5)"

say "Damage: an entry rewritten with a matching new hash (a careful forger)."
# The forger recomputes the hash of the entry they changed, but not the
# chain after it.
line5=$(sed -n '5p' "$WORK/log.good" | sed 's/parallel writer/forged writer/')
body=${line5%,\"hash\":\"*}
if command -v sha256sum > /dev/null 2>&1; then
  newhash=$(printf '%s}' "$body" | sha256sum)
else
  newhash=$(printf '%s}' "$body" | shasum -a 256)
fi
newhash=${newhash%% *}
awk -v n=5 -v repl="$body,\"hash\":\"$newhash\"}" 'NR == n { print repl; next } { print }' "$WORK/log.good" > "$log"
chain
printf '      %s\n' "$CHAIN_LINE"
check "the next entry no longer links: BROKEN at entry 6 (line 6)" contains "$CHAIN_LINE" "BROKEN at entry 6 (line 6)"

say "Damage: a line that is not an entry."
cp "$WORK/log.good" "$log"
printf 'this is not a log entry\n' >> "$log"
chain
printf '      %s\n' "$CHAIN_LINE"
check "names the line" contains "$CHAIN_LINE" "BROKEN at line $((total + 1))"
quiet "$SH" "$SCRIPTS/log-append.sh" checkpoint "written after the damage"
check "the log can still be appended to" [ "$RC" -eq 0 ]
chain
check "and the damage is still reported" contains "$CHAIN_LINE" "Log chain: BROKEN"

say "Damage: the log deleted."
rm -f "$log"
chain
printf '      %s\n' "$CHAIN_LINE"
check "a missing log is BROKEN when the lineage has records" contains "$CHAIN_LINE" "BROKEN. log.jsonl is missing"
check "exit is non-zero" [ "$RC" -ne 0 ]

say "What the chain cannot show (stated in the README): entries cut from the end."
head -n 8 "$WORK/log.good" > "$log"
chain
printf '      %s\n' "$CHAIN_LINE"
check "a log cut short still checks out: this is a known limit" [ "$CHAIN_LINE" = "Log chain: intact (8 entries)." ]

cp "$WORK/log.good" "$log"
chain
check "the undamaged log is intact again" [ "$CHAIN_LINE" = "Log chain: intact ($total entries)." ]

finish
