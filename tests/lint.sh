#!/bin/sh
# Static checks.
#
#   sh tests/lint.sh
#
# - shellcheck, in POSIX sh mode, on every script (skipped if shellcheck
#   is not installed)
# - a syntax check of every script under each POSIX shell found
# - a scan for wording this project has ruled out
# - the skills' pre-approvals (allowed-tools) against a fixed list
# - the copies of shared text inside the skills against skills/_shared/
# - one version, one holder, one repository and one marketplace name in
#   every file that states them
# - the ending of a close, worded the same in the script, the skill and
#   the README
# - no email address anywhere in the plugin

here=$(cd "$(dirname "$0")" && pwd)
plugin=$(cd "$here/.." && pwd)
cd "$plugin" || exit 99
status=0

printf '== shellcheck ==\n'
if command -v shellcheck > /dev/null 2>&1; then
  shellcheck --version | sed -n '2p'
  if shellcheck -s sh -x scripts/*.sh tests/*.sh tests/live/*.sh tests/recording/*.sh; then
    printf 'shellcheck: clean (no warnings) on %s files\n' "$(printf '%s\n' scripts/*.sh tests/*.sh tests/live/*.sh tests/recording/*.sh | grep -c '')"
  else
    status=1
  fi
else
  printf 'shellcheck is not installed: skipped\n'
fi

printf '\n== syntax check under each shell found ==\n'
for shell in sh dash bash ksh mksh yash busybox; do
  command -v "$shell" > /dev/null 2>&1 || continue
  bad=
  for f in scripts/*.sh tests/*.sh tests/live/*.sh tests/recording/*.sh; do
    if [ "$shell" = busybox ]; then
      busybox sh -n "$f" 2> /dev/null || bad="$bad $f"
    else
      "$shell" -n "$f" 2> /dev/null || bad="$bad $f"
    fi
  done
  if [ -z "$bad" ]; then
    printf '%s -n: all scripts parse\n' "$shell"
  else
    printf '%s -n: FAILED on%s\n' "$shell" "$bad"
    status=1
  fi
done

printf '\n== constructs that are not POSIX sh ==\n'
# Belt and braces next to shellcheck, which is the real check: plain text
# patterns for the usual bash-only constructs. (The awk program inside
# stand-down.sh is not shell, so awk keywords are not searched for.)
found=$(grep -nE '(^|[^a-zA-Z_])(local|declare|typeset|source|select|mapfile|readarray) |\[\[ | \]\]|<<<|<\(|\$\{[A-Za-z_]+(//|\^\^|,,|:[0-9])|&>' scripts/*.sh | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
if [ -z "$found" ]; then
  printf 'none found in scripts/\n'
else
  printf '%s\n' "$found"
  status=1
fi

printf '\n== wording ==\n'
# House style, checked so that it holds. Two rules:
#
# 1. Four terms are kept out of the plugin. Each is a metaphor for
#    controlling an agent that was tried while this was being written and
#    dropped, because it promised more than a hook and a script can do.
#    The plugin has one vocabulary (seat, officeholder, tenure, handoff,
#    stand down) and these would be a second one.
# 2. The README makes no claim to be the "first" or the "only" tool of
#    its kind, and does not call the log "tamper-proof": other handoff
#    tools exist, and a hash chain shows tampering without preventing it.
#    The simplest way to keep such claims out is to keep the words out.
#
# The four terms are assembled here so that this file does not contain them.
t1='ra''il'
t2='enve''lope'
t3='lea''se'
t4='comm''and mode'
hits=$(grep -rniwE "$t1|$t2|$t3|$t4" --exclude-dir=.git . || true)
if [ -z "$hits" ]; then
  printf 'the four ruled-out terms: not present anywhere in the plugin\n'
else
  printf '%s\n' "$hits"
  status=1
fi
hits=$(grep -niwE 'first|only|tamper-proof' README.md || true)
if [ -z "$hits" ]; then
  printf 'README.md: no "first", "only" or "tamper-proof"\n'
else
  printf '%s\n' "$hits"
  status=1
fi
if grep -q 'tamper-evident' README.md; then
  printf 'README.md: says "tamper-evident"\n'
else
  printf 'README.md: does not say "tamper-evident"\n'
  status=1
fi

printf '\n== pre-approvals ==\n'
# What a skill may pre-approve in its front matter (allowed-tools): the
# plugin's own scripts in the forms the skill uses, and the files the
# skill writes by hand under .succession/. The charter is not among those
# files: the script writes it when there is none, so that no skill can
# change an existing charter without the owner being asked. Nothing else, and nothing
# broad. An entry that is not in this list fails the check, so a change
# here is a change to what the README promises.
# shellcheck disable=SC2016
# (SC2016: the entries are compared as text; nothing in them is expanded.)
unknown=$(awk '
  BEGIN {
    root = "Bash(sh \"${CLAUDE_PLUGIN_ROOT}/scripts/"
    ok["seat", root "verify.sh\")"] = 1
    ok["seat", root "log-append.sh\" seat *)"] = 1
    ok["seat", root "log-append.sh\" charter)"] = 1
    ok["checkpoint", root "log-append.sh\" checkpoint *)"] = 1
    ok["checkpoint", root "verify.sh\" --draft --checkpoints)"] = 1
    ok["checkpoint", "Edit(.succession/tenures/*/checkpoints.md)"] = 1
    ok["close", root "verify.sh\" --draft)"] = 1
    ok["close", root "log-append.sh\" close *)"] = 1
    ok["close", "Edit(.succession/tenures/*/handoff.md)"] = 1
    ok["close", "Edit(.succession/tenures/*/lessons.md)"] = 1
  }
  FNR == 1 {
    fences = 0
    inlist = 0
    skill = FILENAME
    sub(/\/SKILL\.md$/, "", skill)
    sub(/^.*\//, "", skill)
  }
  /^---[ \t]*$/ { fences++; inlist = 0; next }
  fences != 1 { next }
  /^allowed-tools:/ {
    inlist = 1
    rest = $0
    sub(/^allowed-tools:[ \t]*/, "", rest)
    if (rest != "") printf "%s: allowed-tools must be a list, one entry per line\n", FILENAME
    next
  }
  inlist && /^[ \t]+-[ \t]/ {
    entry = $0
    sub(/^[ \t]+-[ \t]+/, "", entry)
    sub(/[ \t]+$/, "", entry)
    seen++
    if (!((skill, entry) in ok)) printf "%s: not in the list: %s\n", FILENAME, entry
    next
  }
  { inlist = 0 }
  END { if (seen != 10) printf "expected 10 entries in the four skills, found %d\n", seen + 0 }
' skills/*/SKILL.md)
if [ -z "$unknown" ]; then
  printf 'allowed-tools: 10 entries in three skills, each one a plugin script form or a named file under .succession/\n'
else
  printf '%s\n' "$unknown"
  status=1
fi

printf '\n== copies of shared text ==\n'
# A skill cannot read a file in the plugin folder without a permission
# prompt, so each skill carries a copy of the shared text it needs, in a
# block that starts with "~~~~markdown <file>" and ends with "~~~~".
# Every copy must be identical to the file in skills/_shared/.
copies=$(awk '
  function compare(name, text,    src, line, want) {
    src = "skills/_shared/" name
    want = ""
    while ((getline line < src) > 0) want = want line "\n"
    close(src)
    if (want == "") printf "DIFFERS %s: %s is missing or empty\n", FILENAME, src
    else if (want != text) printf "DIFFERS %s: the copy of %s is not identical to %s\n", FILENAME, name, src
    else printf "same %s %s\n", FILENAME, name
  }
  FNR == 1 {
    if (name != "") printf "DIFFERS %s: the block %s is not closed\n", last, name
    name = ""
  }
  { last = FILENAME }
  name == "" && /^~~~~markdown [a-z-]+\.md$/ { name = $2; text = ""; next }
  name != "" && /^~~~~$/ { compare(name, text); name = ""; next }
  name != "" { text = text $0 "\n" }
  END { if (name != "") printf "DIFFERS %s: the block %s is not closed\n", last, name }
' skills/*/SKILL.md)
for want in 'skills/seat/SKILL.md name-themes.md' \
  'skills/checkpoint/SKILL.md claim-format.md' 'skills/close/SKILL.md handoff-format.md' \
  'skills/close/SKILL.md claim-format.md'; do
  case "$copies" in
    *"same $want"* | *"${want% *}: the copy of ${want#* } "* | *"${want% *}: the block ${want#* } "*) ;;
    *) copies="$copies
DIFFERS ${want% *}: no copy of ${want#* }" ;;
  esac
done
case "$copies" in
  *DIFFERS*)
    printf '%s\n' "$copies" | grep DIFFERS
    status=1
    ;;
  *)
    printf '%s copies in the skills, each identical to its file in skills/_shared/\n' "$(printf '%s\n' "$copies" | grep -c '^same ')"
    ;;
esac
# shellcheck disable=SC2016
hits=$(grep -n 'CLAUDE_PLUGIN_ROOT}/skills' skills/*/SKILL.md || true)
if [ -z "$hits" ]; then
  printf 'no skill tells the model to read a file in the plugin folder\n'
else
  printf '%s\n' "$hits"
  status=1
fi

printf '\n== one version, one identity ==\n'
# The manifest is the source. Every other file that states the version,
# the copyright holder, the repository or the marketplace name has to
# agree with it, so that changing one of them cannot be done by halves.
# json_value <file> <key> [<parent key>]: the string value of that key,
# taken after the line that opens the parent when one is given.
json_value() {
  awk -v key="$2" -v parent="${3:-}" '
    BEGIN { armed = (parent == "") }
    !armed && index($0, "\"" parent "\"") { armed = 1; next }
    armed && index($0, "\"" key "\"") {
      v = $0
      sub(/^[^:]*:[ \t]*"/, "", v)
      sub(/".*$/, "", v)
      print v
      exit
    }' "$1"
}
version=$(json_value .claude-plugin/plugin.json version)
holder=$(json_value .claude-plugin/plugin.json name author)
repository=$(json_value .claude-plugin/plugin.json repository)
slug=${repository#https://github.com/}
market=$(json_value .claude-plugin/marketplace.json name)
# same <what> <where> <found> <wanted>
same() {
  if [ -n "$4" ] && [ "$3" = "$4" ]; then
    printf '%s: %s agrees with the manifest\n' "$1" "$2"
  else
    printf '%s: %s says "%s", the manifest says "%s"\n' "$1" "$2" "$3" "$4"
    status=1
  fi
}
# has <what> <file> <text>: the file holds that text, as written.
has() {
  if grep -q -F -- "$3" "$2"; then
    printf '%s: %s agrees with the manifest\n' "$1" "$2"
  else
    printf '%s: %s does not hold "%s"\n' "$1" "$2" "$3"
    status=1
  fi
}
case $version in
  [0-9]*.[0-9]*.[0-9]*) printf 'version: %s\n' "$version" ;;
  *)
    printf 'version: .claude-plugin/plugin.json has no readable version\n'
    status=1
    ;;
esac
same version scripts/verify.sh "$(sed -n 's/^VERSION=//p' scripts/verify.sh)" "$version"
same version README.md "$(sed -n 's/^Version \([0-9][0-9.]*[0-9]\)\. .*$/\1/p' README.md)" "$version"
same version CHANGELOG.md "$(sed -n 's/^## \([0-9][0-9.]*[0-9]\)$/\1/p' CHANGELOG.md | sed -n '1p')" "$version"
same holder .claude-plugin/marketplace.json "$(json_value .claude-plugin/marketplace.json name owner)" "$holder"
same holder LICENSE "$(sed -n 's/^Copyright (c) [0-9]* //p' LICENSE)" "$holder"
case $repository in
  https://github.com/*/*) ;;
  *)
    printf 'repository: .claude-plugin/plugin.json has no readable repository\n'
    status=1
    ;;
esac
has repository README.md "/plugin install succession --marketplace $slug"
has repository README.md "claude plugin marketplace add $slug"
has 'marketplace name' README.md "claude plugin install succession@$market"

printf '\n== the ending of a close ==\n'
# The close skill has the model end with lines that log-append.sh prints,
# and the README shows them. The fixed parts are compared as text.
ending=0
# shellcheck disable=SC2016
# (SC2016: the backticks are text that the skill holds; nothing is run.)
for pair in \
  'scripts/log-append.sh|Tenure closed: %s-%s. The seat is vacant.' \
  'skills/close/SKILL.md|Tenure closed: <Codename>-<NNN>. The seat is vacant.' \
  'README.md|Tenure closed: Sextant-001. The seat is vacant.' \
  'scripts/log-append.sh|Handoff: .succession/tenures/%s/handoff.md' \
  'skills/close/SKILL.md|Handoff: `.succession/tenures/<tenure>/handoff.md`' \
  'README.md|Handoff: .succession/tenures/001-sextant/handoff.md' \
  'skills/close/SKILL.md|Draft check: <the verdict line from step 5>' \
  'README.md|Draft check: 5 claims, 4 pointers verified, 0 failed, 1 not checkable.' \
  'scripts/log-append.sh|Git: the state files in .succession/ are not committed yet. To commit them: git add .succession; git commit -m "Succession: %s closed" -- .succession' \
  'README.md|Git: the state files in .succession/ are not committed yet. To commit them: git add .succession; git commit -m "Succession: Sextant-001 closed" -- .succession' \
  'scripts/log-append.sh|Git: .succession/ is ignored by git in this project, so there is nothing to commit.' \
  'README.md|is ignored by git in this' \
  'skills/close/SKILL.md|<the line that starts with "Git:" in the output of step 6>' \
  'skills/close/SKILL.md|Do not edit the handoff after this' \
  'skills/close/SKILL.md|Do not ask a question and do not offer to do anything.' \
  'skills/close/SKILL.md|do not stage or commit anything under'; do
  if ! grep -q -F -- "${pair#*|}" "${pair%%|*}"; then
    printf '%s does not hold: %s\n' "${pair%%|*}" "${pair#*|}"
    ending=1
  fi
done
if grep -n -i -E 'offer to commit it|say the word' skills/close/SKILL.md; then
  printf 'skills/close/SKILL.md: the close must not end with an offer\n'
  ending=1
fi
if [ "$ending" -eq 0 ]; then
  printf 'the four closing lines read the same in log-append.sh, the close skill and README.md\n'
else
  status=1
fi

printf '\n== addresses ==\n'
# Nothing in the plugin needs an email address, so none is allowed in:
# the tests give git a made-up identity that is not shaped like one.
hits=$(grep -rnIE '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+' \
  README.md PRIVACY.md SECURITY.md CHANGELOG.md LICENSE .gitattributes .claude-plugin hooks scripts skills tests .github 2> /dev/null \
  || true)
if [ -z "$hits" ]; then
  printf 'no email address in the plugin\n'
else
  printf '%s\n' "$hits" | cut -c 1-200
  status=1
fi

printf '\n== network ==\n'
hits=$(grep -nE '(^|[^a-zA-Z_])(curl|wget|nc|ncat|ssh|scp|ftp|telnet|ping|dig|nslookup) |/dev/tcp|https?://' scripts/*.sh hooks/hooks.json | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
if [ -z "$hits" ]; then
  printf 'no network tool or URL in scripts/ or hooks/\n'
else
  printf '%s\n' "$hits"
  status=1
fi

printf '\n'
if [ "$status" -eq 0 ]; then
  printf 'LINT PASSED\n'
else
  printf 'LINT FAILED\n'
fi
exit "$status"
