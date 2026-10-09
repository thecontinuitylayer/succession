#!/bin/sh
# verify.sh - the one thing in Succession that issues a verdict.
#
# Reads the claims in a tenure's handoff, checks each evidence pointer
# against git and the log, checks the hash chain of log.jsonl, compares
# the handoff with the sha256 its close entry carries, writes
# verification.md next to the handoff, records the verdict in the log and
# prints, as its last line:
#
#   N claims, V pointers verified, F failed, U not checkable.
#
# What "pointer verified" means, and all it means: the thing the claim
# points at exists (the commit, the file in that commit, the log entry).
# The sentence beside the pointer is not checked. A script cannot tell
# whether "made before this tenure" or "fixes the bug" is true.
#
# Usage:
#   verify.sh                       the handoff of the most recently closed tenure
#   verify.sh --tenure NNN-name     the handoff of that closed tenure
#   verify.sh --draft               the seated officeholder's own draft; nothing recorded
#   verify.sh --checkpoints         also check the claims in checkpoints.md
#
# Pointer types (anything else is "not checkable"):
#   commit:<sha>               the commit exists and is an ancestor of HEAD
#   file:<path>@<commit-sha>   the file exists in that commit (git cat-file)
#   log:<entry-hash>           the entry exists in log.jsonl
# A commit id is matched against commit objects alone. A branch or a tag
# whose name happens to be hex digits is not taken for one.
#
# Handoff and checkpoint text is data. Nothing named in it is ever run,
# sourced or opened: a pointer is matched against fixed patterns and then
# handed to "git cat-file", "git rev-parse" or "git merge-base" as a plain
# argument. The working tree is never hashed, so line-ending settings
# cannot change a verdict. No file outside <repo>/.succession is read.
#
# Files written, both under <repo>/.succession/tenures/<tenure>:
# verification.md and, for a moment, verification.md.tmp. log-append.sh
# is called to record the verdict. A symbolic link at any path this
# script reads or writes is refused, or removed if it is in the way of
# the short-lived file; it is never followed.
#
# Exit codes: 0 no failed claim, the chain is intact and the handoff is
# the one closed with, 1 a claim failed, the chain is broken or the
# handoff was changed after the close, 2 usage, 3 no git repository, 4 state unreadable.
#
# POSIX sh. No network.

LC_ALL=C
export LC_ALL

VERSION=0.9.0
CR=$(printf '\r')
NL='
'
ZERO=0000000000000000000000000000000000000000000000000000000000000000

die() {
  printf 'succession: %s\n' "$1" >&2
  exit "${2:-1}"
}

usage() {
  printf 'usage: verify.sh [--tenure NNN-name | --draft] [--checkpoints]\n' >&2
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

is_tenure_name() {
  case $1 in
    '' | *[!0-9a-z-]*) return 1 ;;
    [0-9]*-[a-z]*) return 0 ;;
  esac
  return 1
}

is_hex() {
  case $1 in
    '' | *[!0-9a-fA-F]*) return 1 ;;
  esac
  return 0
}

# A commit id as written in a claim: 7 to 64 hex digits and nothing else,
# so it can never be read by git as an option, a ref name or a range.
is_commit_id() {
  is_hex "$1" && [ "${#1}" -ge 7 ] && [ "${#1}" -le 64 ]
}

# Text for display: one line, no control characters, no backticks,
# cut to $2 bytes.
show() {
  if [ "${#1}" -gt "$2" ]; then
    printf '%s' "$1" | tr -d '\000-\037\177' | tr '`' "'" | cut -c "1-$2" | tr -cd '\040-\176'
    printf '...'
  else
    printf '%s' "$1" | tr -d '\000-\037\177' | tr '`' "'"
  fi
}

# md_text <text already through show>: the same text for a Markdown file.
# Claim text is written by a model, or by whoever edited the handoff. In
# verification.md it must stay text: no HTML, no image, no link.
md_text() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/\[/\&#91;/g; s/]/\&#93;/g; s/!/\&#33;/g'
}

# Reads seat.json into SEAT_* without leaving the shell.
# Returns 1 when there is no seat.json, 2 when it cannot be trusted.
read_seat() {
  SEAT_STATUS=
  SEAT_TENURE=
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
      tenure) SEAT_TENURE=$rs_val ;;
    esac
  done < "$S/seat.json"
  case $SEAT_STATUS in
    vacant | occupied | stood_down) ;;
    *) return 2 ;;
  esac
  is_tenure_name "$SEAT_TENURE" || return 2
  return 0
}

# The most recently ended tenure, from the log: LC_TENURE. The log is
# asked and not lineage.jsonl, because the log is the file whose entries
# are chained: a line taken out of the lineage would go unnoticed.
last_closed() {
  LC_TENURE=
  [ -f "$S/log.jsonl" ] || return 0
  [ -L "$S/log.jsonl" ] && return 0
  while IFS= read -r lc_line || [ -n "$lc_line" ]; do
    case $lc_line in
      '{"seq":'*'"type":"close","tenure":"'* | '{"seq":'*'"type":"vacate","tenure":"'*)
        lc_val=${lc_line#*\"tenure\":\"}
        LC_TENURE=${lc_val%%\"*}
        ;;
    esac
  done < "$S/log.jsonl"
  if ! is_tenure_name "$LC_TENURE"; then
    LC_TENURE=
  fi
}

# ---------------------------------------------------------------- log chain

# chain_problem <where> <what>
chain_problem() {
  CHAIN=broken
  CHAIN_COUNT=$((CHAIN_COUNT + 1))
  if [ "$CHAIN_COUNT" -eq 1 ]; then
    CHAIN_HEAD=$1
  fi
  if [ "$CHAIN_COUNT" -le 10 ]; then
    CHAIN_NOTES="$CHAIN_NOTES  - $1: $2$NL"
  fi
}

# Walks log.jsonl once. Sets CHAIN (ok, broken, missing, none),
# CHAIN_ENTRIES, CHAIN_NOTES, and the lists GOOD_HASHES and BAD_HASHES
# used by log: claims.
check_chain() {
  CHAIN=ok
  CHAIN_COUNT=0
  CHAIN_HEAD=
  CHAIN_NOTES=
  CHAIN_ENTRIES=0
  GOOD_HASHES=$NL
  BAD_HASHES=$NL
  cc_file="$S/log.jsonl"
  if [ ! -e "$cc_file" ]; then
    if [ -s "$S/lineage.jsonl" ]; then
      CHAIN=missing
    else
      CHAIN=none
    fi
    return 0
  fi
  refuse_symlink "$cc_file"
  [ -f "$cc_file" ] || die "log.jsonl is not a regular file" 4
  cc_prev_hash=$ZERO
  cc_prev_seq=0
  cc_prev_ok=1
  cc_lineno=0
  while IFS= read -r cc_line || [ -n "$cc_line" ]; do
    cc_lineno=$((cc_lineno + 1))
    cc_line=${cc_line%"$CR"}
    [ -n "$cc_line" ] || continue
    CHAIN_ENTRIES=$((CHAIN_ENTRIES + 1))
    cc_hash=
    cc_prev=
    cc_seq=
    cc_body=
    case $cc_line in
      '{"seq":'*',"prev":"'*'","hash":"'*'"}')
        cc_hash=${cc_line##*,\"hash\":\"}
        cc_hash=${cc_hash%\"\}}
        cc_body=${cc_line%,\"hash\":\"*}
        cc_prev=${cc_body##*,\"prev\":\"}
        cc_prev=${cc_prev%\"}
        cc_seq=${cc_line#\{\"seq\":}
        cc_seq=${cc_seq%%,*}
        ;;
    esac
    case $cc_hash in
      *[!0-9a-f]*) cc_hash= ;;
    esac
    case $cc_prev in
      *[!0-9a-f]*) cc_prev= ;;
    esac
    case $cc_seq in
      *[!0-9]*) cc_seq= ;;
    esac
    if [ "${#cc_hash}" -ne 64 ] || [ "${#cc_prev}" -ne 64 ] || [ -z "$cc_seq" ] || [ "${#cc_seq}" -gt 9 ]; then
      chain_problem "line $cc_lineno" "not a well-formed log entry"
      cc_prev_ok=0
      cc_prev_seq=$((cc_prev_seq + 1))
      continue
    fi
    cc_calc=$(printf '%s}' "$cc_body" | sha256_stdin) || die "no sha256 tool found (need sha256sum or shasum)" 4
    if [ "$cc_calc" = "$cc_hash" ]; then
      GOOD_HASHES="$GOOD_HASHES$cc_hash$NL"
    else
      BAD_HASHES="$BAD_HASHES$cc_hash$NL"
      chain_problem "entry $cc_seq (line $cc_lineno)" "its content does not match its recorded hash, so this entry was edited after it was written"
    fi
    if [ "$cc_prev_ok" -eq 1 ]; then
      if [ "$cc_prev" != "$cc_prev_hash" ]; then
        if [ "$cc_seq" = "$cc_prev_seq" ]; then
          chain_problem "entry $cc_seq (line $cc_lineno)" "it carries the same number as the entry before it and does not link to it, so two entries were written at once, or one of them was altered"
        else
          chain_problem "entry $cc_seq (line $cc_lineno)" "it does not link to the entry before it, so entry $cc_prev_seq or entry $cc_seq was altered, or an entry between them was removed"
        fi
      elif [ "$cc_seq" -ne $((cc_prev_seq + 1)) ]; then
        chain_problem "entry $cc_seq (line $cc_lineno)" "it is numbered $cc_seq where $((cc_prev_seq + 1)) was expected"
      fi
    fi
    cc_prev_hash=$cc_hash
    cc_prev_seq=$cc_seq
    cc_prev_ok=1
  done < "$cc_file"
  return 0
}

chain_line() {
  case $CHAIN in
    ok) printf 'Log chain: intact (%s entries).' "$CHAIN_ENTRIES" ;;
    none) printf 'Log chain: no log yet.' ;;
    missing) printf 'Log chain: BROKEN. log.jsonl is missing although the lineage has records.' ;;
    *) printf 'Log chain: BROKEN at %s. Problems found: %s, in %s entries.' "$CHAIN_HEAD" "$CHAIN_COUNT" "$CHAIN_ENTRIES" ;;
  esac
}

# ------------------------------------------------------------------- claims

set_verdict() {
  J_STATUS=$1
  J_NOTE=$2
}

# resolve_commit <claimed id>: the full id of the one commit object whose
# id starts with the claimed digits, in FULL_ID. Objects are asked for,
# never names: a branch or tag called "deadbeef1" is not a commit id, and
# "git cat-file -e deadbeef1^{commit}" would have taken it for one.
# Returns 1 with the reason in WHY_NOT when there is no such commit.
resolve_commit() {
  FULL_ID=
  WHY_NOT="no such commit in this repository"
  rc_want=$1
  case $rc_want in
    *[A-F]*) rc_want=$(printf '%s' "$rc_want" | tr 'ABCDEF' 'abcdef') ;;
  esac
  rc_count=0
  for rc_id in $(git -C "$root" rev-parse --disambiguate="$rc_want" 2> /dev/null); do
    case $rc_id in
      "$rc_want"*) ;;
      *) continue ;;
    esac
    [ "$(git -C "$root" cat-file -t "$rc_id" 2> /dev/null)" = commit ] || continue
    rc_count=$((rc_count + 1))
    FULL_ID=$rc_id
  done
  if [ "$rc_count" -eq 1 ]; then
    return 0
  fi
  FULL_ID=
  if [ "$rc_count" -gt 1 ]; then
    WHY_NOT="those digits match more than one commit; write more of the id"
  fi
  return 1
}

judge_commit() {
  if ! is_commit_id "$1"; then
    set_verdict unchecked "not a commit id (7 to 64 hex digits); nothing was looked up"
    return 0
  fi
  if ! resolve_commit "$1"; then
    set_verdict failed "$WHY_NOT"
    return 0
  fi
  if git -C "$root" merge-base --is-ancestor "$FULL_ID" HEAD 2>/dev/null; then
    set_verdict verified "the commit exists and is an ancestor of HEAD"
  elif [ "$SHALLOW" = true ]; then
    set_verdict unchecked "the commit exists, but ancestry cannot be decided in a shallow clone"
  else
    set_verdict failed "the commit exists but is not an ancestor of HEAD"
  fi
}

judge_file() {
  case $1 in
    *@*) ;;
    *)
      set_verdict unchecked "expected file:<path>@<commit-sha>"
      return 0
      ;;
  esac
  jf_sha=${1##*@}
  jf_path=${1%@*}
  if ! is_commit_id "$jf_sha"; then
    set_verdict unchecked "the part after @ is not a commit id (7 to 64 hex digits); nothing was looked up"
    return 0
  fi
  while :; do
    case $jf_path in
      ./*) jf_path=${jf_path#./} ;;
      *) break ;;
    esac
  done
  case $jf_path in
    '')
      set_verdict unchecked "empty path"
      return 0
      ;;
    .. | ../* | */.. | */../*)
      set_verdict unchecked "the path contains '..' and could leave the project; nothing was read"
      return 0
      ;;
    /* | '~'* | [A-Za-z]:*)
      set_verdict unchecked "the path is not relative to the project; nothing was read"
      return 0
      ;;
    *\\*)
      set_verdict unchecked "the path contains a backslash; write it with forward slashes"
      return 0
      ;;
    *[[:cntrl:]]*)
      set_verdict unchecked "the path contains a control character"
      return 0
      ;;
  esac
  if ! resolve_commit "$jf_sha"; then
    set_verdict failed "$WHY_NOT"
    return 0
  fi
  jf_sha=$FULL_ID
  jf_type=$(git -C "$root" cat-file -t "$jf_sha:$jf_path" 2>/dev/null)
  case $jf_type in
    blob) ;;
    tree)
      set_verdict failed "that path is a folder in that commit, not a file"
      return 0
      ;;
    *)
      set_verdict failed "no such file in that commit"
      return 0
      ;;
  esac
  jf_then=$(git -C "$root" rev-parse -q --verify "$jf_sha:$jf_path" 2>/dev/null)
  jf_now=$(git -C "$root" rev-parse -q --verify "HEAD:$jf_path" 2>/dev/null)
  if [ -n "$jf_then" ] && [ "$jf_then" = "$jf_now" ]; then
    set_verdict verified "the file exists in that commit and is the same at HEAD"
  elif [ -z "$jf_now" ]; then
    set_verdict changed "the file exists in that commit; it is no longer present at HEAD"
  else
    set_verdict changed "the file exists in that commit; its content at HEAD is different"
  fi
}

judge_log() {
  jl_hash=$1
  case $jl_hash in
    *[A-F]*) jl_hash=$(printf '%s' "$jl_hash" | tr 'ABCDEF' 'abcdef') ;;
  esac
  if ! is_hex "$jl_hash" || [ "${#jl_hash}" -lt 8 ] || [ "${#jl_hash}" -gt 64 ]; then
    set_verdict unchecked "not a log entry hash (8 to 64 hex digits)"
    return 0
  fi
  jl_rest=$GOOD_HASHES
  case $jl_rest in
    *"$NL$jl_hash"*)
      jl_rest=${jl_rest#*"$NL$jl_hash"}
      case $jl_rest in
        *"$NL$jl_hash"*) set_verdict failed "that hash prefix matches more than one log entry" ;;
        *) set_verdict verified "the entry exists in log.jsonl" ;;
      esac
      return 0
      ;;
  esac
  case $BAD_HASHES in
    *"$NL$jl_hash"*)
      set_verdict failed "the entry is in log.jsonl but its content was edited after it was written"
      return 0
      ;;
  esac
  set_verdict failed "no such entry in log.jsonl"
}

judge() {
  case $1 in
    commit:*) judge_commit "${1#commit:}" ;;
    file:*) judge_file "${1#file:}" ;;
    log:*) judge_log "${1#log:}" ;;
    '' | none) set_verdict unchecked "no pointer given; a script cannot check this" ;;
    *) set_verdict unchecked "pointer type not recognised; nothing was run or opened" ;;
  esac
}

# claims_in <file> <label>: every line that starts with "CLAIM [" (after
# optional indentation and a list marker) is one claim.
claims_in() {
  ci_any=0
  while IFS= read -r ci_line || [ -n "$ci_line" ]; do
    ci_line=${ci_line%"$CR"}
    ci_text=${ci_line#"${ci_line%%[! 	]*}"}
    case $ci_text in
      '- '* | '* '* | '+ '*) ci_text=${ci_text#??} ;;
    esac
    ci_text=${ci_text#"${ci_text%%[! 	]*}"}
    case $ci_text in
      'CLAIM ['*) ;;
      *) continue ;;
    esac
    ci_rest=${ci_text#CLAIM \[}
    case $ci_rest in
      *']'*)
        ci_ptr=${ci_rest%%\]*}
        ci_stmt=${ci_rest#*\]}
        judge "$ci_ptr"
        ;;
      *)
        ci_ptr=$ci_rest
        ci_stmt=
        set_verdict unchecked "the pointer has no closing bracket"
        ;;
    esac
    ci_stmt=${ci_stmt#"${ci_stmt%%[! 	]*}"}
    if [ "$ci_any" -eq 0 ]; then
      ci_any=1
      OUT="$OUT${NL}From $2 (the pointer in brackets was checked; the sentence under it was not):$NL"
      MD="$MD${NL}### From \`$2\`$NL$NL"
    fi
    N=$((N + 1))
    case $J_STATUS in
      verified)
        V=$((V + 1))
        ci_word='pointer verified'
        ;;
      changed)
        V=$((V + 1))
        C=$((C + 1))
        ci_word='pointer verified, changed since'
        ;;
      failed)
        F=$((F + 1))
        ci_word='FAILED'
        ;;
      *)
        U=$((U + 1))
        ci_word='not checkable'
        ;;
    esac
    ci_ptr_shown=$(show "$ci_ptr" 200)
    ci_stmt_shown=$(show "$ci_stmt" 300)
    [ -n "$ci_ptr_shown" ] || ci_ptr_shown='(no pointer)'
    [ -n "$ci_stmt_shown" ] || ci_stmt_shown='(no statement)'
    OUT="$OUT  $N. [$ci_word] $ci_ptr_shown$NL     $ci_stmt_shown$NL"
    ci_stmt_md=$(md_text "$ci_stmt_shown")
    if [ "$J_STATUS" != verified ]; then
      OUT="$OUT     -> $J_NOTE$NL"
    fi
    MD="$MD$N. **$ci_word** \`$ci_ptr_shown\`: $J_NOTE$NL   The sentence beside it, which the script did not check: $ci_stmt_md$NL"
  done < "$1"
  return 0
}

# --------------------------------------------------------------------- main

opt_tenure=
opt_draft=0
opt_checkpoints=0
while [ $# -gt 0 ]; do
  case $1 in
    --tenure)
      [ $# -ge 2 ] || usage
      opt_tenure=$2
      shift 2
      ;;
    --draft)
      opt_draft=1
      shift
      ;;
    --checkpoints)
      opt_checkpoints=1
      shift
      ;;
    *) usage ;;
  esac
done
if [ -n "$opt_tenure" ] && [ "$opt_draft" -eq 1 ]; then
  usage
fi

command -v git >/dev/null 2>&1 || die "git was not found. Succession needs git." 3
root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$root" ]; then
  why=$(git rev-parse --show-toplevel 2>&1 | head -n 1)
  die "Succession needs a git repository. Run 'git init' here, or open a project that has one, and try again. (git said: $why)" 3
fi
S="$root/.succession"
here=${0%/*}
[ "$here" != "$0" ] || here=.

if [ ! -d "$S" ]; then
  printf 'No handoff to verify: this project has no Succession history yet.\n'
  exit 0
fi
refuse_symlink "$S"
refuse_symlink "$S/tenures"

SHALLOW=$(git -C "$root" rev-parse --is-shallow-repository 2>/dev/null)
HEAD_SHA=$(git -C "$root" rev-parse -q --verify HEAD 2>/dev/null)
[ -n "$HEAD_SHA" ] || HEAD_SHA='(no commits yet)'

check_chain

# Which tenure is being judged.
target=
if [ "$opt_draft" -eq 1 ]; then
  read_seat || die "no officeholder is seated, so there is no draft to check" 2
  case $SEAT_STATUS in
    occupied | stood_down) target=$SEAT_TENURE ;;
    *) die "no officeholder is seated, so there is no draft to check" 2 ;;
  esac
elif [ -n "$opt_tenure" ]; then
  is_tenure_name "$opt_tenure" || die "not a tenure name: $opt_tenure" 2
  [ -d "$S/tenures/$opt_tenure" ] || die "no such tenure: $opt_tenure" 2
  if read_seat && [ "$SEAT_STATUS" != vacant ] && [ "$SEAT_TENURE" = "$opt_tenure" ]; then
    die "$opt_tenure still holds the seat. Use --draft to check its handoff before it closes." 2
  fi
  target=$opt_tenure
else
  last_closed
  target=$LC_TENURE
fi

chain_exit=0
case $CHAIN in
  broken | missing) chain_exit=1 ;;
esac

if [ -z "$target" ]; then
  printf 'No handoff to verify: no tenure has closed yet.\n'
  chain_line
  printf '\n'
  [ -z "$CHAIN_NOTES" ] || printf '%s' "$CHAIN_NOTES"
  exit "$chain_exit"
fi

tdir="$S/tenures/$target"
refuse_symlink "$tdir"
handoff="$tdir/handoff.md"
checkpoints="$tdir/checkpoints.md"
refuse_symlink "$handoff"
refuse_symlink "$checkpoints"

have_handoff=1
if [ ! -f "$handoff" ] || [ ! -s "$handoff" ]; then
  have_handoff=0
fi
have_checkpoints=0
if [ "$opt_checkpoints" -eq 1 ] && [ -f "$checkpoints" ]; then
  have_checkpoints=1
fi

if [ "$have_handoff" -eq 0 ]; then
  if [ "$opt_draft" -eq 1 ] && [ "$have_checkpoints" -eq 0 ]; then
    die "no draft handoff yet: .succession/tenures/$target/handoff.md is missing or empty" 2
  fi
  if [ "$opt_draft" -eq 0 ]; then
    printf 'No handoff to verify: %s left the seat without one.\n' "$target"
    chain_line
    printf '\n'
    [ -z "$CHAIN_NOTES" ] || printf '%s' "$CHAIN_NOTES"
    exit "$chain_exit"
  fi
fi

N=0
V=0
F=0
U=0
C=0
OUT=
MD=
sources=
if [ "$have_handoff" -eq 1 ]; then
  claims_in "$handoff" "handoff.md"
  sources=".succession/tenures/$target/handoff.md"
fi
if [ "$have_checkpoints" -eq 1 ]; then
  claims_in "$checkpoints" "checkpoints.md"
  sources="${sources:+$sources, }.succession/tenures/$target/checkpoints.md"
fi

verdict="$N claims, $V pointers verified, $F failed, $U not checkable."
chain_text=$(chain_line)

# Is the handoff the one the officeholder closed with? The close entry in
# the log carries its sha256 (carriage returns removed before hashing, so
# a CRLF checkout gives the same answer). Entries written by versions
# 0.1.0 to 0.1.4 carry none; that is said, and is not a failure. A tenure
# closes once, so its earliest close entry is the one asked: a second
# one, added to the end of the log later, does not replace it.
handoff_text=
handoff_exit=0
if [ "$opt_draft" -eq 0 ] && [ "$have_handoff" -eq 1 ]; then
  hf_line=
  if [ -f "$S/log.jsonl" ] && [ ! -L "$S/log.jsonl" ]; then
    hf_line=$(grep -F "\"type\":\"close\",\"tenure\":\"$target\"" "$S/log.jsonl" | sed -n '1p')
  fi
  hf_line=${hf_line%"$CR"}
  # The entry's data begins "<Name>-<NNN> left the seat (<how>). Handoff
  # sha256 <64 hex digits>. <summary>". The sha256 is taken from that
  # place and no other, so a summary cannot pass for it.
  hf_want=
  hf_open=' left the seat ('
  hf_mark='). Handoff sha256 '
  case $hf_line in
    '{"seq":'*"$hf_open"*"$hf_mark"*)
      hf_want=${hf_line#*"$hf_open"}
      hf_how=${hf_want%%"$hf_mark"*}
      case $hf_how in
        close | stand_down)
          hf_want=${hf_want#"$hf_how$hf_mark"}
          hf_want=${hf_want%%.*}
          ;;
        *) hf_want= ;;
      esac
      ;;
  esac
  if ! is_hex "$hf_want" || [ "${#hf_want}" -ne 64 ]; then
    hf_want=
  fi
  if [ -z "$hf_want" ]; then
    handoff_text="Handoff: no sha256 of it was recorded at the close (the close entry is missing, or was written by an older version), so a later change to it cannot be detected."
  else
    hf_have=$(tr -d '\r' < "$handoff" | sha256_stdin) || die "no sha256 tool found (need sha256sum or shasum)" 4
    if [ "$hf_have" = "$hf_want" ]; then
      handoff_text="Handoff: unchanged since the close (its sha256 is the one in the close entry of the log)."
    else
      handoff_text="Handoff: CHANGED since the close. Its sha256 is not the one in the close entry of the log, so the claims here are not the ones the officeholder closed with."
      handoff_exit=1
    fi
  fi
fi
checked_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

if [ "$opt_draft" -eq 1 ]; then
  printf 'Succession verify: DRAFT of %s (nothing is recorded)\n' "$target"
else
  printf 'Succession verify: handoff of %s\n' "$target"
fi
if [ "$N" -eq 0 ]; then
  printf '\nNo CLAIM lines found, so there is nothing a script can check.\n'
fi
printf '%s\n' "$OUT"
if [ "$C" -gt 0 ]; then
  printf 'Changed since their claimed commit: %s of the files whose pointer was verified.\n' "$C"
fi
printf '%s\n' "$chain_text"
[ -z "$CHAIN_NOTES" ] || printf '%s' "$CHAIN_NOTES"
[ -z "$handoff_text" ] || printf '%s\n' "$handoff_text"

record_exit=0
if [ "$opt_draft" -eq 0 ]; then
  vfile="$tdir/verification.md"
  refuse_symlink "$vfile"
  fresh_file "$vfile.tmp"
  {
    printf '# Verification of the handoff of %s\n\n' "$target"
    printf 'Issued by scripts/verify.sh (Succession %s). The script alone decides\n' "$VERSION"
    printf 'each status below; no model wrote or edited this verdict.\n\n'
    printf 'What was checked: each pointer (a commit, a file in a commit, a log\n'
    printf 'entry) against git and the log. What was not: the sentence beside it.\n'
    printf '"pointer verified" means the thing pointed at exists. It does not mean\n'
    printf 'the sentence is true.\n\n'
    printf 'Verdict: %s\n' "$verdict"
    printf '%s\n' "$chain_text"
    [ -z "$handoff_text" ] || printf '%s\n' "$handoff_text"
    printf 'Checked at: %s\n' "$checked_at"
    printf 'HEAD: %s\n' "$HEAD_SHA"
    printf 'Sources: %s\n\n' "$sources"
    printf '## Claims\n'
    if [ "$N" -eq 0 ]; then
      printf '\nThe handoff has no CLAIM lines.\n'
    fi
    printf '%s\n' "$MD"
    printf '## Log chain\n\n'
    printf '%s\n' "$chain_text"
    [ -z "$CHAIN_NOTES" ] || printf '\n%s' "$CHAIN_NOTES"
    printf '\n## Reading the statuses\n\n'
    printf '%s\n' '- pointer verified: the commit, the file in that commit or the log entry exists. The sentence beside the pointer was not checked and may still be wrong.'
    printf '%s\n' '- pointer verified, changed since: the file was in the claimed commit; it differs at HEAD.'
    printf '%s\n' '- FAILED: the pointer does not check out. The claim is not supported by its evidence.'
    printf '%s\n' '- not checkable: there is no pointer a script can check. It may be true; someone has to look.'
  } > "$vfile.tmp" || die "cannot write $vfile" 4
  mv -f "$vfile.tmp" "$vfile" || die "cannot write $vfile" 4
  printf 'Written: .succession/tenures/%s/verification.md\n' "$target"
  record_text="$verdict $chain_text"
  [ -z "$handoff_text" ] || record_text="$record_text $handoff_text"
  if record=$(sh "$here/log-append.sh" verify "$target" "$record_text"); then
    printf '%s\n' "$record"
  else
    printf 'WARNING: the verdict could not be recorded in log.jsonl.\n'
    record_exit=4
  fi
fi

printf '%s\n' "$verdict"

if [ "$F" -gt 0 ] || [ "$chain_exit" -ne 0 ] || [ "$handoff_exit" -ne 0 ]; then
  exit 1
fi
exit "$record_exit"
