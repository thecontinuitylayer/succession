# Changelog

## 0.9.0

The public starting point. Before it, the plugin was built and tested in
private under the numbers 0.1.0 to 0.1.6; logs written by those builds
are still read.

What a new user should know about this version:

- The verdict line reads `N claims, V pointers verified, F failed, U not
  checkable.` "Pointer verified" means the commit, the file in a commit
  or the log entry a claim points at exists. The sentence beside the
  pointer is not checked, and the output says so each time.
- A commit id in a claim is matched against commits alone. A branch or
  tag whose name is hex digits is not accepted.
- The close records the sha256 of the handoff in the log, and the
  verifier reports a handoff changed after its close. A close written by
  an earlier build has no sha256; that is reported as not recorded.
- The seat gate reads the log, not the lineage, to find the tenure that
  ended last.
- No script follows a symbolic link under `.succession/`, at the paths of
  its short-lived files and lock folder included.
- A stale lock is cleared by one waiter at a time, and a writer holds
  the lock only once it has created the lock's `pid` file, so that
  writers behind a stale lock cannot give two entries the same number.
- A write that finds the lock taken waits for as long as the lock keeps
  changing hands, up to 90 seconds, and for 20 seconds behind one
  process that keeps it. A write that gives up writes nothing, says who
  holds the lock and exits 4. (With a wait of 12 seconds, the last of
  twelve writers at once gave up under Git Bash, where a write takes
  about half a second.)
- A lock is cleared when the process named in it is gone and has been
  seen in the lock for two seconds, not at first sight, and the writer
  that clears it says so. A writer looks at the lock once more just
  before it adds to the log.
- The stop phrase's hook gives up on a held lock after three seconds by
  the clock,
  has the officeholder say that the stand-down could not be recorded,
  and gives Claude Code a warning to show the owner directly.
- The session-start hook takes the verdict from the log's last verify
  entry, not from `verification.md`. It and the seat script warn when
  the tenure folders show more than the state files do, or when
  `seat.json` and the log's last seat entry disagree (after `git stash`,
  `git checkout` or `git reset --hard` on a committed record).
- The charter is written from the template by a script. No edit to a
  charter is approved in advance.
- A close ends with four fixed lines, the last of which gives the
  command line that commits `.succession/`.

Not in this version: a real session on macOS, an interactive session in
a terminal, and a run of the one-line install. The README lists them
under "Not tested yet".
