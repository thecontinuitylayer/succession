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
