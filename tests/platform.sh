#!/bin/sh
# shellcheck disable=SC2016,SC3028,SC2002
# (SC2016: the labels below show shell and awk text literally, inside
# single quotes on purpose. SC3028: OSTYPE and BASH_VERSION are read to
# report them; they are empty in shells that do not set them. SC2002: two
# probes pipe a file through cat because the pipe is what they look at.)
#
# Facts about this machine's shell and text tools.
#
#   sh tests/platform.sh
#
# It prints what it finds and judges nothing: it exits 0 whatever the
# answers are. The question it was written for is which tools show a
# carriage return (CR) at the end of a line and which hide it. The plugin
# and its tests must not depend on the ones that hide it.
#
# What it showed in October 2026: on Linux and macOS every tool passes
# the CR through. Under Git Bash (Git for Windows 2.55: GNU grep 3.0,
# GNU sed 4.9, GNU awk 5.4) grep, sed and awk drop the CR of a CRLF line
# from what they read, and the shell drops a CR LF at the very end of a
# command substitution. tr, wc, tail, sort, cat and "read -r" pass it
# through there too.
#
# Each line gives what was seen here, then what is seen when the CR is
# passed through untouched.

LC_ALL=C
export LC_ALL

base=${SUCCESSION_TESTBED:-${TMPDIR:-/tmp}}
mkdir -p "$base" || exit 0
work=$(mktemp -d "$base/succession-platform.XXXXXX") || exit 0
cr=$(printf '\r')
crlf="$work/crlf.txt"
printf 'one\r\ntwo\r\n' > "$crlf"
printf 'one\ntwo\n' > "$work/lf.txt"

# n <command...>: the command's output with spaces removed. A command that
# prints nothing is shown as "no output", with its exit code.
n() {
  n_out=$("$@" 2> /dev/null)
  n_rc=$?
  [ -n "$n_out" ] || n_out="no output (exit $n_rc)"
  printf '%s' "$n_out" | tr -d ' \t'
}

printf '== System ==\n'
printf 'system: %s\n' "$(uname -s -r -m 2> /dev/null)"
printf 'OS=%s OSTYPE=%s MSYSTEM=%s\n' "${OS-unset}" "${OSTYPE-unset}" "${MSYSTEM-unset}"
printf 'TMPDIR=%s PWD=%s\n' "${TMPDIR-unset}" "$PWD"
if [ -n "${BASH_VERSION-}" ]; then
  printf 'this shell: bash %s\n' "$BASH_VERSION"
else
  printf 'this shell: not bash\n'
fi
for tool in sh git awk grep sed tr wc tail sort sha256sum shasum perl cygpath; do
  printf '%s: %s\n' "$tool" "$(command -v "$tool" 2> /dev/null || printf 'not found')"
done
printf 'git: %s\n' "$(git --version 2> /dev/null)"
printf 'awk: %s\n' "$( (awk --version 2> /dev/null || awk -W version 2> /dev/null || awk -version 2> /dev/null) | sed -n '1p')"
printf 'grep: %s\n' "$( (grep --version 2> /dev/null || printf 'no --version') | sed -n '1p')"
printf 'sed: %s\n' "$( (sed --version 2> /dev/null || printf 'no --version') | sed -n '1p')"
printf 'core.autocrlf, every level: %s\n' "$(git config --show-origin --get-all core.autocrlf 2> /dev/null | tr '\n\t' '; ' || true)"

printf '\n== Paths ==\n'
if command -v cygpath > /dev/null 2>&1; then
  tmp_win=$(cygpath -m "$base" 2> /dev/null)
  printf 'cygpath -m %s: %s\n' "$base" "$tmp_win"
  case $tmp_win in
    [A-Za-z]:/*)
      (
        cd -P -- "/${tmp_win%%:*}${tmp_win#?:}" 2> /dev/null || exit 0
        printf 'PWD after cd -P into that folder by its drive path: %s\n' "$PWD"
      )
      ;;
  esac
fi
(
  cd -P -- "$work" 2> /dev/null || exit 0
  printf 'PWD after cd -P into a new folder under %s: %s\n' "$base" "$PWD"
)

printf '\n== The sample file: two lines, "one" and "two", each ending CR LF (10 bytes) ==\n'
printf 'wc -c < file: %s (10)\n' "$(n wc -c < "$crlf")"

printf '\n== Shell ==\n'
printf 'length of $(printf "\\r"): %s (1)\n' "${#cr}"
whole=$(cat "$crlf")
printf 'length of $(cat file): %s (9; 7 if the shell drops CR)\n' "${#whole}"
IFS= read -r line < "$crlf"
printf 'length of the opening line as read by "read -r": %s (4; 3 if CR is dropped)\n' "${#line}"
printf 'printf "a\\r\\n" | wc -c: %s (3)\n' "$(printf 'a\r\n' | n wc -c)"

printf '\n== grep ==\n'
printf 'grep -c "<CR>$" file: %s (2; 0 if grep hides CR)\n' "$(n grep -c "$cr\$" "$crlf")"
printf 'grep -c "<CR>$" < file: %s (2)\n' "$(n grep -c "$cr\$" < "$crlf")"
printf 'cat file | grep -c "<CR>$": %s (2)\n' "$(cat "$crlf" | n grep -c "$cr\$")"
printf 'grep -c "<CR>" file: %s (2)\n' "$(n grep -c "$cr" "$crlf")"
printf 'grep -c "e$" file: %s (0; 1 if grep drops CR before matching)\n' "$(n grep -c 'e$' "$crlf")"
printf 'grep -U -c "<CR>$" file: %s (2 where -U is supported)\n' "$(n grep -U -c "$cr\$" "$crlf")"
printf 'grep -c "" file: %s (2)\n' "$(n grep -c '' "$crlf")"
printf 'bytes in "grep one file": %s (5; 4 if grep drops CR from its output)\n' "$(grep one "$crlf" 2> /dev/null | n wc -c)"

printf '\n== tr, wc, tail, sed, sort ==\n'
printf 'tr -cd "\\r" < file | wc -c: %s (2)\n' "$(tr -cd '\r' < "$crlf" | n wc -c)"
printf 'tr -d "\\r" < file | wc -c: %s (8)\n' "$(tr -d '\r' < "$crlf" | n wc -c)"
printf 'wc -l < file: %s (2)\n' "$(n wc -l < "$crlf")"
printf 'tail -n 1 file | wc -c: %s (5)\n' "$(tail -n 1 "$crlf" | n wc -c)"
printf 'sed -n 1p file | wc -c: %s (5; 4 if sed drops CR)\n' "$(sed -n '1p' "$crlf" | n wc -c)"
printf 'sort file | wc -c: %s (10)\n' "$(sort "$crlf" | n wc -c)"
printf 'cat file | wc -c: %s (10)\n' "$(cat "$crlf" | n wc -c)"

printf '\n== awk ==\n'
printf 'sum of length($0), file as argument: %s (8; 6 if awk drops CR)\n' "$(n awk '{ t += length($0) } END { print t }' "$crlf")"
printf 'sum of length($0), file on standard input: %s (8)\n' "$(n awk '{ t += length($0) } END { print t }' < "$crlf")"
printf 'bytes written by printf "a\\r\\n": %s (3)\n' "$(awk 'BEGIN { printf "a\r\n" }' | n wc -c)"
printf 'bytes written by print "a": %s (2; 3 if awk writes CR LF)\n' "$(awk 'BEGIN { print "a" }' | n wc -c)"

printf '\n== git ==\n'
(
  mkdir "$work/src" && cd "$work/src" || exit 0
  git init -q . 2> /dev/null
  git config user.name "Test Owner"
  git config user.email "owner.invalid"
  git config commit.gpgsign false
  git config core.autocrlf false
  cp "$work/lf.txt" lf.txt
  git add lf.txt > /dev/null 2>&1
  git commit -q -m "one LF file" > /dev/null 2>&1
  printf 'size of the committed file in git: %s (8)\n' "$(n git cat-file -s HEAD:lf.txt)"
  git clone -q -c core.autocrlf=true "$work/src" "$work/clone" 2> /dev/null
  printf 'size of that file in a clone made with core.autocrlf=true: %s (10)\n' "$(n wc -c < "$work/clone/lf.txt")"
  printf 'carriage returns in it, by tr and wc: %s (2)\n' "$(tr -cd '\r' < "$work/clone/lf.txt" | n wc -c)"
  printf 'lines in it that grep "<CR>$" finds: %s (2; 0 if grep hides CR)\n' "$(n grep -c "$cr\$" "$work/clone/lf.txt")"
  printf 'git ls-files --eol in the clone: %s\n' "$(git -C "$work/clone" ls-files --eol lf.txt 2> /dev/null | tr -s ' \t' ' ')"
)

printf '\n== sha256 ==\n'
if command -v sha256sum > /dev/null 2>&1; then
  sum=$(printf 'abc' | sha256sum)
elif command -v shasum > /dev/null 2>&1; then
  sum=$(printf 'abc' | shasum -a 256)
else
  sum='no tool found'
fi
printf 'sha256 of "abc": %s (ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad)\n' "${sum%% *}"

rm -rf "$work"
exit 0
