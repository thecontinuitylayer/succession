---
name: checkpoint
description: Record a dated checkpoint for the seated officeholder, saying what was done and where the proof is in git. Use when the owner asks for a checkpoint, or when a piece of work worth recording is finished.
allowed-tools:
  - Bash(sh "${CLAUDE_PLUGIN_ROOT}/scripts/log-append.sh" checkpoint *)
  - Bash(sh "${CLAUDE_PLUGIN_ROOT}/scripts/verify.sh" --draft --checkpoints)
  - Edit(.succession/tenures/*/checkpoints.md)
---

# Record a checkpoint

A checkpoint is a dated note of what was done and where the proof is. Your
successor's verifier can check the pointers you leave.

Tool rules for this skill:

- Run each command shown below as one command by itself, exactly as
  written: no `cd`, `;`, `&&`, pipe or redirect. Claude Code pre-approves
  the plugin's scripts in that form for the turn that uses this skill.
  Anything joined to one of them can make it ask the owner.
- Read files with the Read tool. Write the files under `.succession/`
  with the Write or Edit tool, never from the shell.

1. **Confirm you hold the seat.** `.succession/seat.json` must read
   `"status": "occupied"`; note the `tenure` value. If it does not, tell the
   owner and stop (the `succession:seat` skill seats an officeholder).

2. **Gather evidence from git, not from memory.** Run
   `git log --oneline -n 10` and `git status --short`, each by itself, and
   no other git command: Claude Code runs these two without asking, and
   may ask the owner about others (`git ls-tree`, `git show`, `git diff`).
   You do not need them. The check in step 5 looks up every pointer for
   you. A pointer can name
   committed work and nothing else. If the work is not committed, commit it
   when the charter lets you, or say in the note that it is uncommitted.
   That is about the project's own files. `.succession/` is the record,
   not the work: do not report it as uncommitted, in the note or to the
   owner.

3. **Log it.**

   ```
   sh "${CLAUDE_PLUGIN_ROOT}/scripts/log-append.sh" checkpoint "<one-line summary>"
   ```

   The script prints `Log entry: <hash>` and `Entry time (UTC): <time>`.

4. **Write the note.** Append a section to
   `.succession/tenures/<tenure>/checkpoints.md` (the file is already
   there):

   ```markdown
   ## <entry time> - <one-line summary>

   Log entry: <hash>

   - CLAIM [commit:<sha>] <what that commit did>
   - CLAIM [file:<path>@<sha>] <what that file holds as of that commit>
   - CLAIM [none] <a fact a script cannot check, and how to confirm it>

   Notes: anything the next reader needs.
   ```

   The entry time is the one the script printed, copied as printed. Do
   not make up a time. The claim rules are in the block `claim-format.md`
   at the end of this skill.

5. **Check your pointers.**

   ```
   sh "${CLAUDE_PLUGIN_ROOT}/scripts/verify.sh" --draft --checkpoints
   ```

   Fix a pointer you mistyped. Do not invent a pointer so that a line
   passes, and do not delete a true statement because it is not checkable.
   "pointer verified" means the commit, file or log entry exists. It does
   not mean your sentence is true, so do not tell the owner that the
   script confirmed what you wrote.

6. **Tell the owner** in a line or two what was recorded, and stop there.
   Do not ask a question and do not offer to commit. The close gives the
   owner the one command that commits `.succession/`.

## Bundled text

A copy of a file in the plugin's `skills/_shared/` folder, kept here so
that nothing outside the project has to be read.

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
