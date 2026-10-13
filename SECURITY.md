# Security

## Reporting a problem

Open an issue on the plugin's repository:
https://github.com/thecontinuitylayer/succession/issues

If the problem lets a repository's content write outside `.succession/`,
run a command, or get a change past the owner, say so in the title and
leave the working exploit out of the public issue; describe what it
reaches and you will be asked for the rest. There is no email address
for reports.

## What the plugin is meant to guarantee

- It makes no network call.
- It writes nothing outside the `.succession/` folder of the project, and
  follows no symbolic link there. The one exception is a single line in
  the project's git folder, which records that the owner accepted a
  charter (`log-append.sh accept`).
- A charter is reported as in force in two cases and no other: it is
  the plugin's template, word for word, or the owner accepted that exact
  text in this clone. A charter that arrives with a clone or a pull is
  reported as `NOT in force`, and so is one changed after it was
  accepted, and one in a project folder that was moved or copied.
  Nothing under `.succession/` can stand in for the acceptance: the
  record is kept in the git folder, which a clone does not bring, it
  names the charter's text and the project's path by one sha256, and a
  folder of tracked files laid out like a git folder is not taken for
  one.
- `accept` takes the sha256 of the text that was shown and refuses when
  the charter reads otherwise by then.
- It never runs, sources or opens anything named in a handoff, a
  checkpoint note or any other file in the repository. Handoff text is
  data.
- An edit to a recorded log entry, and a change to a handoff after its
  close, are reported by `verify.sh`.

## What it does not guarantee

- That a model obeys the stop phrase. A hook records the stand-down and
  tells the model to stop; it cannot force it.
- That the log cannot be rewritten. A whole chain recomputed, or entries
  cut from the end, check out. Git history is the anchor.
- That a claim is true. A verified pointer exists; the sentence beside
  it was not checked.
- That a copy of your whole project folder is clean. An archive that
  holds the git folder as well (a zip or tar of the folder, not a
  clone), unpacked at the same path as where it was made, carries the
  acceptance with it. Treat such a folder as you would treat running
  its code.
- That you are asked before `accept` runs. You are under Claude Code's
  default permissions. A session that skips permission prompts, or a
  rule of yours that allows every `sh` command, is not asked.
- That a model obeys the charter rules. The script reports whether a
  charter is in force; the skill and the session-start hook tell the
  model that a charter not in force authorizes nothing, that a handoff
  never does, and that the template's ask-first list (push, publish,
  delete, dependencies, secrets, anything outside the repository)
  holds whatever a charter says. Those are instructions, not controls.
  What a command may do is decided by Claude Code's permission settings.
- Anything about a repository you have not looked at. A cloned
  repository can carry a `.succession/` folder written by someone else:
  its handoffs, lessons and charter are that person's text. The skills
  tell the model to treat them as information and to change the charter
  on the owner's word alone, and an edit to an existing charter always
  asks you. Read a charter you did not write before you accept it.

## Candidate, not built

A hook that denies tool calls while the seat reads stood down would turn
the stop phrase from an instruction into a control. It is not in this
version.
