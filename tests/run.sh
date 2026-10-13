#!/bin/sh
# Runs the Succession test suite. POSIX sh; needs git and a sha256 tool.
#
#   sh tests/run.sh
#
# Parts:
#   three-tenures.sh   three tenures, planted false claims, a hand-edited log
#   stand-down.sh      the owner's stop phrase
#   claims.sh          hostile and malformed claims
#   session-start.sh   the 2,000-character limit with a 50-entry lineage; the name, the last
#                      checkpoint and the session title an occupied seat adds
#   compact.sh         the note a compaction leaves in the log
#   name.sh            a seat by name alone, and turning handoffs on from it
#   first-start.sh     a name at the first session start in a fresh project
#   log.sh             several writers at once, and each kind of damage to the log
#   close.sh           the last line of a close: where .succession/ stands in git
#   safety.sh          no write through a link, the handoff bound to the log, state put back by git
#   charter.sh         a charter is in force as the template or on the owner's word, and not otherwise
#
# Related scripts that are run on their own:
#   sh tests/autocrlf.sh   the whole suite again in a core.autocrlf=true clone
#   sh tests/lint.sh       shellcheck and a POSIX syntax check
#   sh tests/bench.sh      wall time of the two hooks
#   sh tests/platform.sh   how this machine's shell and text tools treat CRLF

here=$(cd "$(dirname "$0")" && pwd)
failed=
for part in three-tenures stand-down claims session-start compact name first-start log close safety charter; do
  if ! "${SUCCESSION_SH:-sh}" "$here/$part.sh"; then
    failed="$failed $part"
  fi
done

printf '\n'
if [ -n "$failed" ]; then
  printf 'SUITE FAILED:%s\n' "$failed"
  exit 1
fi
printf 'SUITE PASSED: three-tenures stand-down claims session-start compact name first-start log close safety charter\n'
exit 0
