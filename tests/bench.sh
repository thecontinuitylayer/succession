#!/bin/sh
# shellcheck disable=SC3028
# (SC3028: EPOCHREALTIME is used as a clock when the shell has it, which
# bash 5 does. Other shells leave it empty and another clock is used.)
#
# Wall time of the two hooks.
#
#   sh tests/bench.sh
#
# The UserPromptSubmit hook runs on every prompt and the SessionStart hook
# at every session start, so what they cost matters, above all on Windows
# where starting a process is slow. Each case below is run several times
# from this shell, the way Claude Code's hook shell runs it
# (sh "<plugin>/scripts/<hook>.sh" with the hook input on standard input),
# and the median is reported.
#
# Environment:
#   SUCCESSION_BENCH_SCRIPTS    folder of the scripts to measure
#                               (default: this plugin's scripts)
#   SUCCESSION_BENCH_LABEL      a name for that folder in the output
#   SUCCESSION_BENCH_RUNS       runs per case (default: 15)
#   SUCCESSION_BENCH_LIMIT_MS   if set, exit 1 when the median of case (a)
#                               or case (b) is above this many milliseconds

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

BSCRIPTS=${SUCCESSION_BENCH_SCRIPTS:-$SCRIPTS}
LABEL=${SUCCESSION_BENCH_LABEL:-this checkout}
RUNS=${SUCCESSION_BENCH_RUNS:-15}
LIMIT=${SUCCESSION_BENCH_LIMIT_MS:-}
NL='
'

# ---------------------------------------------------------------- the clock

CLOCK=seconds
if [ -n "${EPOCHREALTIME-}" ]; then
  CLOCK=shell
else
  probe=$(date +%s%N 2> /dev/null)
  case $probe in
    '' | *[!0-9]*) ;;
    *) [ "${#probe}" -lt 16 ] || CLOCK=nanodate ;;
  esac
  if [ "$CLOCK" = seconds ] && command -v perl > /dev/null 2>&1; then
    CLOCK=perl
  fi
fi

# now_ms: the time in milliseconds, in NOW.
now_ms() {
  case $CLOCK in
    shell)
      nm=$EPOCHREALTIME
      NOW=$((${nm%[.,]*} * 1000 + (1${nm#*[.,]} - 1000000) / 1000))
      ;;
    nanodate)
      nm=$(date +%s%N)
      NOW=$((nm / 1000000))
      ;;
    perl) NOW=$(perl -MTime::HiRes=time -e 'printf "%d\n", time() * 1000') ;;
    *) NOW=$(($(date +%s) * 1000)) ;;
  esac
}

# What reading the clock twice costs, so that it can be taken off.
i=0
sum=0
while [ "$i" -lt 10 ]; do
  now_ms
  t0=$NOW
  now_ms
  sum=$((sum + NOW - t0))
  i=$((i + 1))
done
CLOCK_COST=$((sum / 10))

# ------------------------------------------------------------ the projects

title "Hook timings"
new_project bench
printf 'x\n' > README.md
commit_all "Initial commit" > /dev/null
quiet "$SH" "$BSCRIPTS/log-append.sh" seat Sextant

# A repository that has no .succession folder, and a folder with no repository.
mkdir "$WORK/no-state" "$WORK/no-repo"
git init -q "$WORK/no-state"

# A project with fifty officeholders. The state is written here directly,
# in the format log-append.sh writes, because building it with a hundred
# script calls takes minutes on Windows. The hook under test only reads it.
P50="$WORK/fifty"
mkdir "$P50"
git init -q "$P50"
ZEROS=0000000000000000000000000000000000000000000000000000000000000000
folders=
lineage=
i=1
while [ "$i" -le 50 ]; do
  num=$(printf '%03d' "$i")
  folders="$folders $P50/.succession/tenures/$num-navigation-instrument-number-$num"
  lineage="$lineage{\"ordinal\":\"$num\",\"codename\":\"Navigation-Instrument-Number-$num\",\"tenure\":\"$num-navigation-instrument-number-$num\",\"event\":\"seated\",\"ts\":\"2026-01-01T00:00:00Z\",\"entry\":\"$ZEROS\"}$NL"
  if [ "$i" -lt 50 ]; then
    lineage="$lineage{\"ordinal\":\"$num\",\"codename\":\"Navigation-Instrument-Number-$num\",\"tenure\":\"$num-navigation-instrument-number-$num\",\"event\":\"closed\",\"ts\":\"2026-01-01T00:00:00Z\",\"how\":\"close\",\"summary\":\"Bench entry $i\",\"last_words\":\"None.\",\"entry\":\"$ZEROS\"}$NL"
  fi
  i=$((i + 1))
done
# shellcheck disable=SC2086
# (SC2086: the list of folders is meant to be split into words.)
mkdir -p $folders
for d in $folders; do
  case $d in
    */050-*) ;;
    *) printf '# Handoff\n\n- CLAIM [none] bench\n' > "$d/handoff.md" ;;
  esac
done
printf '%s' "$lineage" > "$P50/.succession/lineage.jsonl"
printf '# Charter\n' > "$P50/.succession/charter.md"
printf '# Verification\n\nVerdict: 1 claims, 0 pointers verified, 0 failed, 1 not checkable.\nLog chain: intact (99 entries).\n' \
  > "$P50/.succession/tenures/049-navigation-instrument-number-049/verification.md"
cat > "$P50/.succession/seat.json" <<'JSON'
{
  "status": "occupied",
  "ordinal": "050",
  "codename": "Navigation-Instrument-Number-050",
  "tenure": "050-navigation-instrument-number-050",
  "seated": "2026-01-01T00:00:00Z",
  "updated": "2026-01-01T00:00:00Z"
}
JSON
check "the fifty-officeholder project is read as such" contains \
  "$(CLAUDE_PROJECT_DIR="$P50" "$SH" "$BSCRIPTS/session-start.sh" 2>&1)" "Lineage: 50 officeholders so far"

# ----------------------------------------------------------- the hook input

doc() {
  printf '{"session_id":"abc123","transcript_path":"/nonexistent/transcript.jsonl","cwd":"/nonexistent","permission_mode":"default","hook_event_name":"UserPromptSubmit","prompt":"%s"}' "$1"
}
prompt=
while [ "${#prompt}" -lt 480 ]; do
  prompt="${prompt}Please look at the retry setting and tell me what it does. "
done
doc "$prompt" > "$WORK/normal.json"
doc 'Stand down, Sextant' > "$WORK/phrase.json"
big=
while [ "${#big}" -lt 100000 ]; do
  big="$big$prompt$prompt$prompt$prompt"
done
doc "$big" > "$WORK/big.json"
: > "$WORK/empty.sh"
printf '      the ordinary prompt is %s characters; the hook input holding it is %s bytes\n' "${#prompt}" "$(wc -c < "$WORK/normal.json" | tr -d ' \t')"

# ---------------------------------------------------------------- the cases

# run_case <name>: one run of one case.
run_case() {
  case $1 in
    0) "$SH" "$WORK/empty.sh" < "$WORK/normal.json" ;;
    a) CLAUDE_PROJECT_DIR="$WORK/no-state" "$SH" "$BSCRIPTS/stand-down.sh" < "$WORK/normal.json" ;;
    a2) CLAUDE_PROJECT_DIR="$WORK/no-repo" "$SH" "$BSCRIPTS/stand-down.sh" < "$WORK/normal.json" ;;
    b) CLAUDE_PROJECT_DIR="$PROJ" "$SH" "$BSCRIPTS/stand-down.sh" < "$WORK/normal.json" ;;
    b2) CLAUDE_PROJECT_DIR="$PROJ" "$SH" "$BSCRIPTS/stand-down.sh" < "$WORK/big.json" ;;
    c) CLAUDE_PROJECT_DIR="$PROJ" "$SH" "$BSCRIPTS/stand-down.sh" < "$WORK/phrase.json" ;;
    d) CLAUDE_PROJECT_DIR="$P50" "$SH" "$BSCRIPTS/session-start.sh" < /dev/null ;;
    d2) CLAUDE_PROJECT_DIR="$WORK/no-state" "$SH" "$BSCRIPTS/session-start.sh" < /dev/null ;;
  esac
}

# measure <case> <runs> <description>
# Case (c) gets a fresh officeholder before each run, outside the timed part.
measure() {
  ms_all=
  ms_i=0
  while [ "$ms_i" -lt "$2" ]; do
    if [ "$1" = c ]; then
      "$SH" "$BSCRIPTS/log-append.sh" vacate "bench" > /dev/null 2>&1
      "$SH" "$BSCRIPTS/log-append.sh" seat Sextant > /dev/null 2>&1
    fi
    now_ms
    ms_t0=$NOW
    run_case "$1" > "$WORK/out.txt" 2>&1
    now_ms
    ms_d=$((NOW - ms_t0 - CLOCK_COST))
    [ "$ms_d" -ge 0 ] || ms_d=0
    ms_all="$ms_all$ms_d$NL"
    ms_i=$((ms_i + 1))
  done
  ms_sorted=$(printf '%s' "$ms_all" | sort -n)
  MEDIAN=$(printf '%s\n' "$ms_sorted" | sed -n "$((($2 + 1) / 2))p")
  ms_min=$(printf '%s\n' "$ms_sorted" | sed -n '1p')
  ms_max=$(printf '%s\n' "$ms_sorted" | tail -n 1)
  printf '  %-5s %6s ms   (fastest %s, slowest %s, %s runs)   %s\n' "($1)" "$MEDIAN" "$ms_min" "$ms_max" "$2" "$3"
}

printf '\n      scripts measured: %s (%s)\n' "$LABEL" "$BSCRIPTS"
printf '      system: %s; shell: %s; clock: %s, reading it costs about %s ms, taken off each figure\n\n' \
  "$(uname -s -m 2> /dev/null)" "$SH" "$CLOCK" "$CLOCK_COST"
printf '  case  median\n'

measure 0 "$RUNS" "an empty script, for scale: what starting sh costs here"
m_0=$MEDIAN
measure a "$RUNS" "stand-down.sh, repository without .succession, ordinary prompt"
m_a=$MEDIAN
measure a2 "$RUNS" "stand-down.sh, folder with no repository, ordinary prompt"
measure b "$RUNS" "stand-down.sh, seat held, ordinary prompt"
m_b=$MEDIAN
check "case (b) changed nothing: the seat is still held" grep -q '"status": "occupied"' .succession/seat.json
measure b2 5 "stand-down.sh, seat held, a prompt of about 100,000 characters"
measure c 5 "stand-down.sh, seat held, the exact stop phrase (recorded each time)"
m_c=$MEDIAN
check "case (c) recorded a stand-down" grep -q '"status": "stood_down"' .succession/seat.json
measure d "$RUNS" "session-start.sh, lineage of 50 officeholders"
m_d=$MEDIAN
measure d2 "$RUNS" "session-start.sh, repository without .succession"

printf '\nBENCH %s | %s | empty=%s a=%s b=%s c=%s d=%s (median ms)\n' "$LABEL" "$(uname -s 2> /dev/null)" "$m_0" "$m_a" "$m_b" "$m_c" "$m_d"

if [ -n "$LIMIT" ]; then
  check "case (a) is under $LIMIT ms (median $m_a ms)" [ "$m_a" -lt "$LIMIT" ]
  check "case (b) is under $LIMIT ms (median $m_b ms)" [ "$m_b" -lt "$LIMIT" ]
fi

finish
