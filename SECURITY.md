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
  follows no symbolic link there.
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
- Anything about a repository you have not looked at. A cloned
  repository can carry a `.succession/` folder written by someone else:
  its handoffs, lessons and charter are that person's text. The skills
  tell the model to treat them as information and to change the charter
  on the owner's word alone, and an edit to an existing charter always
  asks you. Read a charter you did not write before you seat anyone
  under it.

## Candidate, not built

A hook that denies tool calls while the seat reads stood down would turn
the stop phrase from an instruction into a control. It is not in this
version.
