# shellcheck shell=sh
# shellcheck disable=SC2034,SC2154
# (SC2034, SC2154: this file is sourced. The variables it sets are used by
# the scripts that source it, and "here" is set by them before they do.)
#
# Shared helpers for the Succession tests. POSIX sh. Sourced, not run:
#   here=$(cd "$(dirname "$0")" && pwd); . "$here/lib.sh"
#
# Environment:
#   SUCCESSION_SH             shell used to run the plugin scripts (default: sh)
#   SUCCESSION_TESTBED        folder for throwaway projects (default: $TMPDIR or /tmp)
#   SUCCESSION_TEST_KEEP=1    keep the throwaway projects afterwards
#   SUCCESSION_TEST_AUTOCRLF  value of core.autocrlf in throwaway projects (default: false)
#   SUCCESSION_VERDICTS       file that receives one line per verdict, for comparing runs
#   SUCCESSION_DEMO=1         pause between steps (for the terminal recording)

LC_ALL=C
export LC_ALL

PLUGIN=$(cd "$here/.." && pwd)
SCRIPTS="$PLUGIN/scripts"
SH=${SUCCESSION_SH:-sh}
PASS=0
FAIL=0
FAILED=
WORK=
FAKE_SHA=0123456789abcdef0123456789abcdef01234567

# The tests must see only the hook environment they set themselves.
unset CLAUDE_PROJECT_DIR

title() {
  printf '\n== %s ==\n' "$1"
}

say() {
  printf '\n-- %s\n' "$1"
  pace
}

pace() {
  if [ -n "${SUCCESSION_DEMO:-}" ]; then
    sleep "${SUCCESSION_DEMO_PAUSE:-1}"
  fi
}

ok() {
  PASS=$((PASS + 1))
  printf '  ok    %s\n' "$1"
}

bad() {
  FAIL=$((FAIL + 1))
  FAILED="$FAILED  FAILED CHECK: $1
"
  printf '  FAIL  %s\n' "$1"
}

# check <description> <command...>
check() {
  ck_desc=$1
  shift
  if "$@"; then
    ok "$ck_desc"
  else
    bad "$ck_desc"
  fi
}

contains() {
  case $1 in
    *"$2"*) return 0 ;;
  esac
  return 1
}

# plain_file <path>: a regular file that is not a symbolic link.
plain_file() {
  [ -f "$1" ] && [ ! -L "$1" ]
}

# absent <path>...: nothing is at any of the paths, not even a dangling link.
absent() {
  for ab_path in "$@"; do
    if [ -e "$ab_path" ] || [ -L "$ab_path" ]; then
      return 1
    fi
  done
  return 0
}

lacks() {
  case $1 in
    *"$2"*) return 1 ;;
  esac
  return 0
}

last_line() {
  printf '%s\n' "$1" | tail -n 1
}

# verdict <text>: remembered for comparing two runs of the suite.
verdict() {
  if [ -n "${SUCCESSION_VERDICTS:-}" ]; then
    printf '%s\n' "$1" >> "$SUCCESSION_VERDICTS"
  fi
}

# run <label> <command...>: prints the label and the real output, and
# leaves the output in OUT and the exit code in RC.
run() {
  rn_label=$1
  shift
  printf '\n  $ %s\n' "$rn_label"
  OUT=$("$@" 2>&1)
  RC=$?
  if [ -n "$OUT" ]; then
    printf '%s\n' "$OUT" | sed 's/^/      /'
  fi
  printf '      (exit %s)\n' "$RC"
  pace
}

# quiet <command...>: same, without printing.
quiet() {
  OUT=$("$@" 2>&1)
  RC=$?
}

# The hash printed on a "Log entry: <hash>" line of OUT.
entry_hash() {
  eh=${1##*Log entry: }
  printf '%s' "${eh%%[!0-9a-f]*}"
}

# entry_time_ok <output> <log file>: the output holds one "Entry time
# (UTC):" line, straight after its "Log entry:" line, and the time on it
# is the "ts" of that entry in the log.
entry_time_ok() {
  et_hash=$(entry_hash "$1")
  et_time=$(printf '%s\n' "$1" | awk '
    /^Entry time \(UTC\): / {
      all++
      if (prev ~ /^Log entry: /) {
        paired++
        t = $0
        sub(/^Entry time \(UTC\): /, "", t)
      }
    }
    { prev = $0 }
    END { if (all == 1 && paired == 1) print t }')
  case $et_time in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
    *) return 1 ;;
  esac
  [ "${#et_hash}" -eq 64 ] || return 1
  grep -q "\"ts\":\"$et_time\".*\"hash\":\"$et_hash\"" "$2"
}

file_sum() {
  if [ -f "$1" ]; then
    cksum < "$1"
  else
    printf 'absent'
  fi
}

# cr_count <file>: how many carriage-return bytes the file holds.
# Counted with tr and wc, and never with grep, sed or awk. Under Git Bash
# (Git for Windows) those three drop the CR of a CRLF line before they
# look at it, so a pattern for "CR at the end of a line" matches nothing
# there even in a file that is CRLF throughout. tr, wc, tail, sort, cat
# and the shell's own read pass the CR through on every system tested.
# tests/platform.sh prints what each tool does on the machine at hand.
cr_count() {
  tr -cd '\r' < "$1" | wc -c | tr -d ' \t'
}

# line_count <file>: how many line-feed bytes the file holds.
line_count() {
  wc -l < "$1" | tr -d ' \t'
}

# all_crlf <file>: true when the file has lines and every one of them
# ends with carriage return, line feed.
all_crlf() {
  ac_cr=$(cr_count "$1")
  ac_lf=$(line_count "$1")
  [ "$ac_lf" -gt 0 ] && [ "$ac_cr" -eq "$ac_lf" ]
}

# no_cr <file>: true when the file holds no carriage return at all.
no_cr() {
  [ "$(cr_count "$1")" -eq 0 ]
}

# to_crlf <file>: rewrites a file that has LF line endings so that every
# line ends with CRLF. Shell builtins write the bytes, so no tool's idea
# of text mode is involved.
to_crlf() {
  while IFS= read -r tc_line || [ -n "$tc_line" ]; do
    printf '%s\r\n' "$tc_line"
  done < "$1" > "$1.crlf"
  cat "$1.crlf" > "$1"
  rm -f "$1.crlf"
}

# probe_check: the two helpers above are themselves checked on this
# machine, so that a later "has CRLF" or "has no CR" result means something.
probe_check() {
  printf 'one\r\ntwo\r\n' > "$WORK/probe-crlf.txt"
  printf 'one\ntwo\n' > "$WORK/probe-lf.txt"
  check "the carriage-return count works on this machine (2 in a CRLF sample, 0 in an LF sample)" \
    [ "$(cr_count "$WORK/probe-crlf.txt")$(cr_count "$WORK/probe-lf.txt")" = "20" ]
  cp "$WORK/probe-lf.txt" "$WORK/probe-made.txt"
  to_crlf "$WORK/probe-made.txt"
  check "a file rewritten with CRLF is byte-for-byte the CRLF sample" cmp -s "$WORK/probe-made.txt" "$WORK/probe-crlf.txt"
}

# watch_spawns: from here on, the plugin scripts run with a PATH that
# starts with a folder of stand-ins for the external tools they could
# call. Each stand-in writes its name to $SPAWN_LOG and then runs the real
# tool, so a test can say which processes a hook started. (A tool that
# the shell provides itself, such as awk in busybox, has no stand-in.)
SPAWN_TOOLS="git awk grep sed tr cut tail head date cat wc sort mkdir rmdir rm mv cp sleep sha256sum shasum dirname basename uname expr env printf od cmp"
watch_spawns() {
  SPAWN_DIR="$WORK/stand-ins"
  SPAWN_LOG="$WORK/spawn.log"
  mkdir -p "$SPAWN_DIR" || exit 99
  for ws_tool in $SPAWN_TOOLS; do
    ws_real=$(command -v "$ws_tool" 2> /dev/null) || continue
    case $ws_real in
      /*) ;;
      *) continue ;;
    esac
    # shellcheck disable=SC2016
    # (SC2016: the dollar signs belong to the stand-in script being written.)
    printf '#!/bin/sh\necho "%s" >> "$SPAWN_LOG"\nexec "%s" "$@"\n' "$ws_tool" "$ws_real" > "$SPAWN_DIR/$ws_tool"
    chmod +x "$SPAWN_DIR/$ws_tool"
  done
  export SPAWN_LOG
  : > "$SPAWN_LOG"
}

# spawned: the tools started since the last call, on one line.
spawned() {
  sp_list=
  while IFS= read -r sp_line || [ -n "$sp_line" ]; do
    sp_list="$sp_list${sp_list:+ }$sp_line"
  done < "$SPAWN_LOG"
  : > "$SPAWN_LOG"
  printf '%s' "$sp_list"
}

# new_project <name>: makes a throwaway git project and enters it.
new_project() {
  np_base=${SUCCESSION_TESTBED:-${TMPDIR:-/tmp}}
  # Under Git Bash, /tmp is a mount point and not a folder on a drive. The
  # same folder is used by its drive path (/c/Users/...), which is the kind
  # of path a real project has there.
  if command -v cygpath > /dev/null 2>&1; then
    np_win=$(cygpath -m "$np_base" 2> /dev/null)
    case $np_win in
      [A-Za-z]:/*)
        np_drive=$(printf '%s' "${np_win%%:*}" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
        np_base="/$np_drive${np_win#?:}"
        ;;
    esac
  fi
  mkdir -p "$np_base" || exit 99
  WORK=$(mktemp -d "$np_base/succession-$1.XXXXXX") || exit 99
  PROJ="$WORK/project"
  mkdir "$PROJ" || exit 99
  cd "$PROJ" || exit 99
  git init -q . || exit 99
  git symbolic-ref HEAD refs/heads/main
  git config user.name "Test Owner"
  git config user.email "owner.invalid"
  git config commit.gpgsign false
  git config core.autocrlf "${SUCCESSION_TEST_AUTOCRLF:-false}"
  git config core.safecrlf false
  printf '      throwaway project: %s\n' "$PROJ"
}

# commit_all <message>: commits everything and prints the new commit id.
commit_all() {
  git add -A > /dev/null 2>&1
  git commit -q -m "$1" > /dev/null 2>&1
  git rev-parse HEAD
}

# finish: prints the tally, removes the throwaway project, exits 0 or 1.
finish() {
  printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
  # Said again at the end, where the log of a hosted machine is read.
  [ -z "$FAILED" ] || printf '%s' "$FAILED"
  cd / || exit 99
  if [ -n "$WORK" ] && [ -z "${SUCCESSION_TEST_KEEP:-}" ] && [ "$FAIL" -eq 0 ]; then
    rm -rf "$WORK"
  elif [ -n "$WORK" ]; then
    printf 'kept: %s\n' "$WORK"
  fi
  if [ "$FAIL" -eq 0 ]; then
    exit 0
  fi
  exit 1
}
