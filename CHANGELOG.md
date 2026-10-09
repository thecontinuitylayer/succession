# Changelog

## 0.9.1

A session that ends without a close, or whose context is compacted,
comes back knowing its name and its last checkpoint. Nothing else is
new.

- **Session start, with the seat held.** The hook's text now also gives
  the tenure's last checkpoint as the log has it (at most 200
  characters), tells the model that it is the seated officeholder, has
  it read the charter and the latest checkpoint note, and has it open
  its next reply with its name and what that checkpoint recorded. After
  a compaction it says that the note and the log are the record to
  trust over memory. With the seat vacant, an officeholder stood down,
  or a warning to give, the text is as it was.
- **Session title.** A second session-start hook gives Claude Code the
  officeholder's name and number as the session's title, for a new
  session, a resumed one and a fork. A session that already has a title
  keeps it. The title is a JSON document of its own; the status stays
  plain text.
- **Before a compaction.** A new hook adds one entry to the log, manual
  or automatic. The entry has the type `checkpoint` and a fixed text, so
  a log that holds it reads the same to the verifier of 0.9.0. The hook
  prints nothing, always exits 0 and waits three seconds at most for the
  lock; it cannot hold a compaction up.
- **Install on Windows.** The README says what to do when
  `claude plugin marketplace add` fails with `EBUSY` and `EPERM` while
  VS Code is open on a folder that holds your `.claude` folder.
- **Run for real since 0.9.0:** 0.9.0 installed from the public
  repository with the two shell commands, in a terminal session on
  Windows; and this version's new behaviour in headless sessions on
  Linux, a real `/compact` included. The README lists what is still
  not tested: an automatic compaction, an interactive session with this
  version, macOS, and the one-line install.

The entry format, the claim format, the stop phrase and the verdict are
unchanged, and so is the meaning of every entry type.

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
