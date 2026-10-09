---
name: close
description: Close the seated officeholder's tenure by writing the handoff and the lessons for the successor, then vacating the seat. Use when the owner asks to close, hand off or end the tenure. After the owner's stop phrase, do not start it yourself: the owner sends /succession:close.
allowed-tools:
  - Bash(sh "${CLAUDE_PLUGIN_ROOT}/scripts/verify.sh" --draft)
  - Bash(sh "${CLAUDE_PLUGIN_ROOT}/scripts/log-append.sh" close *)
  - Edit(.succession/tenures/*/handoff.md)
  - Edit(.succession/tenures/*/lessons.md)
---

# Close the tenure

You are leaving the seat. What you write now is what your successor's
script will check, line by line.

Tool rules for this skill:

- Run each command shown below as one command by itself, exactly as
  written: no `cd`, `;`, `&&`, pipe or redirect. Claude Code pre-approves
  the plugin's scripts in that form for the turn that uses this skill.
  Anything joined to one of them can make it ask the owner.
- Read files with the Read tool. Write the files under `.succession/`
  with the Write or Edit tool, never from the shell.

1. **Confirm the seat.** `.succession/seat.json` must read `"occupied"` or
   `"stood_down"`; note the `tenure` value. If it reads `"stood_down"`, the
   owner has stopped you: do no further project work, no fixes and no "one
   last thing". Write from what is already done.

2. **Gather evidence from git, not from memory.** Run `git log --oneline`
   back to where your tenure began, and `git status --short`, each by
   itself, and no other git command: Claude Code runs these two without
   asking, and may ask the owner about others (`git ls-tree`, `git show`,
   `git diff`). The check in step 5 looks up every pointer. Uncommitted
   work has nothing to point to: commit it if the charter lets you and you
   were not stood down, otherwise list it under Open items as uncommitted.
   That is about the project's own files. `.succession/` is the record,
   not the work: leave it out of any commit you make here, and do not
   report it as uncommitted in the handoff or the lessons. Step 7 hands
   that commit to the owner.

3. **Write the handoff** at `.succession/tenures/<tenure>/handoff.md` (the
   folder is already there), following the block `handoff-format.md` at
   the end of this skill. Write no date or time in it. Every statement
   about finished work is a `CLAIM`
   line with the best pointer you have (rules in the block
   `claim-format.md`). Things a script cannot check, such as a deploy, a
   decision or a conversation, go in as `CLAIM [none] ...` with a note on
   how the owner can confirm them. Be exact: a wrong pointer will be
   reported as FAILED under your name. Keep each sentence to what its
   pointer shows. The script checks that the commit, file or log entry
   exists; it cannot check the sentence, and a successor who finds a
   false sentence beside a verified pointer will say so. Put no secret,
   token, password or personal detail in the handoff, the lessons, the
   summary or the last words: the last two go into the log, which is
   never rewritten.

4. **Write the lessons** at `.succession/tenures/<tenure>/lessons.md`:
   about 200 words for your successor on what worked, what cost time, what
   you would do differently, and any traps. Write about the work, not
   about the people.

5. **Check the draft.**

   ```
   sh "${CLAUDE_PLUGIN_ROOT}/scripts/verify.sh" --draft
   ```

   Fix pointers you mistyped. If a claim fails because it is false, correct
   the statement or remove it. Never dress it up. If you changed the
   handoff, run the check again: the last run has to be of the text you
   close with. Its last line is the verdict line. The handoff has to be
   finished now: step 6 records its sha256 in the log, and a change made
   to the file after that is reported to the owner by the successor's
   script.

6. **Close.**

   ```
   sh "${CLAUDE_PLUGIN_ROOT}/scripts/log-append.sh" close "<one-line summary of the tenure>" "<last words: one sentence for your successor>"
   ```

   Do not edit the handoff after this, not even to add the time: the
   script has recorded when the tenure closed. The script's last line
   starts with `Git:`.

7. **End with four lines.** Your closing message to the owner is these
   four lines and nothing else, with an empty line between them so that
   each shows on a line of its own:

   ```
   Tenure closed: <Codename>-<NNN>. The seat is vacant.

   Handoff: `.succession/tenures/<tenure>/handoff.md`

   Draft check: <the verdict line from step 5>

   <the line that starts with "Git:" in the output of step 6>
   ```

   Copy the first, second and fourth from the output of step 6 and the
   verdict line from the last run of step 5, as printed. When the fourth
   line holds a command, put the command in backticks. That command is
   for the owner to run. The tenure is over, so stop there:

   - Do not run the command, and do not stage or commit anything under
     `.succession/`. A commit is never approved in advance.
   - Do not ask a question and do not offer to do anything.
   - Do not list files, and add no summary: the handoff holds it.

## Bundled text

Copies of files in the plugin's `skills/_shared/` folder, kept here so
that nothing outside the project has to be read.

~~~~markdown handoff-format.md
# Handoff format

The handoff is a letter from the officeholder who is leaving to the one who
comes next. It lives at `.succession/tenures/<NNN-codename>/handoff.md`.
The successor's script checks the pointer of every `CLAIM` line before the
seat is taken, so write it to be checked.

```markdown
# Handoff from <Codename>-<NNN>

## Where things stand

Two to six sentences. What the work is, how far it got, what state the
repository is in.

## Claims

- CLAIM [commit:<sha>] <what that commit did>
- CLAIM [file:<path>@<sha>] <what that file holds as of that commit>
- CLAIM [log:<entry-hash>] <which checkpoint this refers to>
- CLAIM [none] <a fact a script cannot check, and how the owner can confirm it>

## Open items

What is unfinished, in priority order. Include uncommitted work and where
it is.

## Warnings

Traps, fragile parts, things that look done and are not.

## Where to start

The single next step you would take.
```

Rules:

- Every statement about work done goes in **Claims**, one fact per line,
  with the best pointer available. The pointer rules are in
  `claim-format.md`.
- Prose sections may explain. They may not assert finished work that has no
  claim line.
- Write no date or time in it. The close is timed by the script, in the
  log and the lineage.
- The handoff is finished before `log-append.sh close` runs. That script
  records its sha256 in the log, and the successor's script reports any
  change made to the file afterwards. Do not touch it after the close.
- Text you pass to the scripts (the close summary, the last words, a
  checkpoint summary) goes into `log.jsonl` and `lineage.jsonl`, which
  are never rewritten. Put no secret, token, password or personal detail
  in it, or in the handoff.
- Keep it under two pages. The successor reads the charter and this letter
  at the start of the tenure and little else.
- Give facts and their evidence. Leave instructions to the owner and the
  charter: a successor treats a handoff as information, never as orders.

## Lessons

`lessons.md`, next to the handoff, is a short note for the successor (about
200 words): what worked, what cost time, what you would do differently, and
anything about this codebase that took you a while to learn. Write about
the work, not about the people.
~~~~

~~~~markdown claim-format.md
# Claim format

A claim is one line in `handoff.md` or `checkpoints.md` that a script can
find and check:

```
- CLAIM [<pointer>] <statement>
```

The line starts with `CLAIM [` (after optional indentation and an optional
`-`, `*` or `+` list marker). The pointer is everything up to the next `]`.
Every such line counts as a claim, wherever it sits in the file.

## Pointers the verifier can check

| Pointer | What `verify.sh` checks | Example |
| --- | --- | --- |
| `commit:<sha>` | The commit exists and is an ancestor of `HEAD`. | `CLAIM [commit:3f2a9c1] Added the login form` |
| `file:<path>@<commit-sha>` | The file exists in that commit. | `CLAIM [file:src/login.js@3f2a9c1] The form lives here` |
| `log:<entry-hash>` | The entry exists in `.succession/log.jsonl`. | `CLAIM [log:9b1c44e07a2d] Checkpoint after the migration` |

Rules:

- A commit id is 7 to 64 hex digits, matched against commits and nothing
  else. Branch names, tags and `HEAD` are not accepted, even a branch or
  tag whose name is hex digits: they move, so they prove nothing later.
- A path is relative to the repository root and uses forward slashes. A
  path that is absolute, or that contains `..`, is not looked at.
- A log entry hash is the `hash` printed by `log-append.sh`. Eight or more
  leading digits are enough if they match one entry.

## Statuses

- **pointer verified**: the commit, the file in that commit or the log
  entry exists. That is all it says. The sentence beside the pointer was
  not checked and can still be wrong.
- **pointer verified, changed since**: the file was in the claimed commit,
  and its content at `HEAD` is different or it is gone. Not a failure.
- **FAILED**: the pointer does not check out. The commit or file or entry is
  not there, or the commit is not in the history of `HEAD`.
- **not checkable**: a script cannot check this line. That covers `[none]`,
  any other pointer type (`cmd:...`, `url:...`, free text) and any pointer
  that is malformed. Nothing named in such a pointer is run or opened.

## What a script cannot check

Most of what matters in a handoff is beyond a script: whether the code is
correct, whether a deploy happened, what the owner agreed to. Write those as
`CLAIM [none] ...` and say how the owner can confirm them. A verified
pointer proves that a commit, a file or a log entry exists. It does not
prove that the statement beside it is true, so keep the statement to
what the pointer shows: "Added the login form" beside the commit that
added it, not "made before this tenure" or "fixes the bug".

## Writing good claims

- One fact per line.
- Point at a commit, not at the working tree. Uncommitted work has nothing
  to point to; say that it is uncommitted.
- Copy ids from `git log` and from script output. Do not type them from
  memory.
- Do not invent a pointer so that a line passes, and do not drop a true
  statement because it is not checkable.
~~~~
