#!/bin/sh
# The whole suite again under core.autocrlf=true.
#
#   sh tests/autocrlf.sh
#
# 1. Runs tests/run.sh here and keeps the verdict lines.
# 2. Clones this plugin with core.autocrlf=true, as Git for Windows does
#    by default, and runs tests/run.sh from that clone, in throwaway
#    projects that also have core.autocrlf=true.
# 3. Compares the two sets of verdict lines. They must be identical.
#
# In a git checkout of the plugin the clone is made from the last commit,
# so commit before running this. In a copy of the plugin that is not a
# git checkout of its own (an unpacked archive, for example), a throwaway
# repository is made from the files as they are, and the clone is made
# from that.

here=$(cd "$(dirname "$0")" && pwd)
plugin=$(cd "$here/.." && pwd)
run_sh=${SUCCESSION_SH:-sh}
unset CLAUDE_PROJECT_DIR

command -v git > /dev/null 2>&1 || {
  printf 'autocrlf.sh needs git.\n' >&2
  exit 2
}

base=${SUCCESSION_TESTBED:-${TMPDIR:-/tmp}}
mkdir -p "$base" || exit 99
work=$(mktemp -d "$base/succession-autocrlf.XXXXXX") || exit 99

# What the clones are made from: this checkout, or a throwaway repository
# made from a copy of this folder when it is not a checkout of its own.
source_repo=$plugin
if [ -e "$plugin/.git" ] && git -C "$plugin" rev-parse -q --verify HEAD > /dev/null 2>&1; then
  if [ -n "$(git -C "$plugin" status --porcelain 2> /dev/null)" ]; then
    printf 'note: uncommitted changes in the plugin are not part of the clone.\n'
  fi
else
  printf 'note: this folder is not a git checkout of its own; the clone is made from a throwaway repository that holds a copy of it.\n'
  source_repo="$work/source"
  mkdir "$source_repo" || exit 99
  cp -R "$plugin"/. "$source_repo"/ || exit 99
  rm -rf "$source_repo/.git"
  (
    cd "$source_repo" || exit 99
    git init -q . || exit 99
    git config user.name "Test Owner"
    git config user.email "owner.invalid"
    git config commit.gpgsign false
    git config core.autocrlf false
    git config core.safecrlf false
    git add -A > /dev/null 2>&1 || exit 99
    git commit -q -m "A copy of the plugin" > /dev/null 2>&1 || exit 99
  ) || {
    printf 'autocrlf.sh could not make a repository from a copy of the plugin.\n' >&2
    exit 99
  }
fi

# report_run <exit code> <log>: the times the stop-phrase hook took, and,
# for a run that failed, each failed check with the line before it and
# the "diag:" lines of the log tests. The
# log itself is in a folder that a hosted machine throws away, so what is
# needed to understand a failure has to be printed here.
report_run() {
  grep -e 'the hook answered in [0-9]' -e 'writers were done after' "$2" | sed 's/^ */  /'
  [ "$1" -ne 0 ] || return 0
  printf '  the run failed (exit %s). Failed checks, each with the line before it:\n' "$1"
  awk '/^  FAIL / { if (prev != "") print "    | " prev; print "    | " $0 } { prev = $0 }' "$2" | sed -n '1,60p'
  # What the log tests print about writers that went wrong: how many
  # entries, which numbers twice, each writer's exit code and message.
  grep '^      diag: ' "$2" | sed -n '1,120p' | sed 's/^ */    | /'
}

printf '== 1. Suite in this checkout (core.autocrlf=false in the throwaway projects) ==\n'
SUCCESSION_TEST_AUTOCRLF=false SUCCESSION_VERDICTS="$work/verdicts-lf.txt" "$run_sh" "$plugin/tests/run.sh" > "$work/suite-lf.log" 2>&1
rc_lf=$?
tail -n 1 "$work/suite-lf.log"
report_run "$rc_lf" "$work/suite-lf.log"

printf '\n== 2. Suite in a clone made with core.autocrlf=true ==\n'
git clone -q -c core.autocrlf=true "$source_repo" "$work/plugin-crlf" || exit 99
printf 'core.autocrlf in the clone: %s\n' "$(git -C "$work/plugin-crlf" config core.autocrlf)"

# Carriage returns are counted as bytes with tr and wc. grep is not used
# for this: the grep in Git for Windows drops the CR of a CRLF line before
# matching, so it reports no carriage returns in a file that is full of
# them (see tests/platform.sh).
cr_count() {
  tr -cd '\r' < "$1" | wc -c | tr -d ' \t'
}
printf 'one\r\ntwo\r\n' > "$work/probe-crlf.txt"
printf 'one\ntwo\n' > "$work/probe-lf.txt"
probe_ok=1
if [ "$(cr_count "$work/probe-crlf.txt")$(cr_count "$work/probe-lf.txt")" = "20" ]; then
  printf 'the carriage-return count works on this machine (2 in a CRLF sample, 0 in an LF sample)\n'
else
  printf 'the carriage-return count does NOT work on this machine\n'
  probe_ok=0
fi

with_cr=0
checked=0
for f in "$work"/plugin-crlf/scripts/*.sh "$work"/plugin-crlf/tests/*.sh "$work"/plugin-crlf/hooks/hooks.json "$work"/plugin-crlf/skills/*/*.md "$work"/plugin-crlf/.claude-plugin/*.json; do
  checked=$((checked + 1))
  if [ "$(cr_count "$f")" -ne 0 ]; then
    with_cr=$((with_cr + 1))
    printf '  has carriage returns: %s\n' "${f#"$work"/plugin-crlf/}"
  fi
done
printf 'scripts, hook, skill and manifest files in the clone that contain a carriage return: %s of %s\n' "$with_cr" "$checked"

# Control: a second clone, with .gitattributes taken away. One script is
# checked out again and must then arrive with CRLF. If it did not, the
# count above would prove nothing.
git clone -q -c core.autocrlf=true "$source_repo" "$work/control" || exit 99
git -C "$work/control" rm -q --cached .gitattributes
rm -f "$work/control/.gitattributes" "$work/control/scripts/verify.sh"
git -C "$work/control" checkout -q -- scripts/verify.sh
control_cr=$(cr_count "$work/control/scripts/verify.sh")
control_lf=$(wc -l < "$work/control/scripts/verify.sh" | tr -d ' \t')
printf 'control, a clone with .gitattributes taken away: scripts/verify.sh is checked out with %s carriage returns in %s lines\n' "$control_cr" "$control_lf"
control_ok=0
if [ "$control_cr" -gt 0 ] && [ "$control_cr" -eq "$control_lf" ]; then
  control_ok=1
fi
SUCCESSION_TEST_AUTOCRLF=true SUCCESSION_VERDICTS="$work/verdicts-crlf.txt" "$run_sh" "$work/plugin-crlf/tests/run.sh" > "$work/suite-crlf.log" 2>&1
rc_crlf=$?
tail -n 1 "$work/suite-crlf.log"
report_run "$rc_crlf" "$work/suite-crlf.log"

printf '\n== 3. Verdicts, side by side ==\n'
printf '%s verdict lines in this checkout, %s in the clone\n' "$(grep -c '' "$work/verdicts-lf.txt")" "$(grep -c '' "$work/verdicts-crlf.txt")"
sed 's/^/  /' "$work/verdicts-crlf.txt"

status=0
if [ "$rc_lf" -ne 0 ] || [ "$rc_crlf" -ne 0 ]; then
  printf '\nFAILED: a suite run did not pass (here: exit %s, clone: exit %s). Logs: %s\n' "$rc_lf" "$rc_crlf" "$work"
  status=1
elif [ "$probe_ok" -ne 1 ]; then
  printf '\nFAILED: carriage returns cannot be counted on this machine, so the clone could not be checked.\n'
  status=1
elif [ "$with_cr" -ne 0 ]; then
  printf '\nFAILED: the clone has plugin files with CRLF line endings. Logs: %s\n' "$work"
  status=1
elif [ "$control_ok" -ne 1 ]; then
  printf '\nFAILED: the control did not behave as expected (see above). Logs: %s\n' "$work"
  status=1
elif ! cmp -s "$work/verdicts-lf.txt" "$work/verdicts-crlf.txt"; then
  printf '\nFAILED: the verdicts differ.\n'
  diff "$work/verdicts-lf.txt" "$work/verdicts-crlf.txt"
  status=1
else
  printf '\nAUTOCRLF PASSED: both runs passed and every verdict line is identical.\n'
fi

if [ "$status" -eq 0 ] && [ -z "${SUCCESSION_TEST_KEEP:-}" ]; then
  rm -rf "$work"
else
  printf 'kept: %s\n' "$work"
fi
exit "$status"
