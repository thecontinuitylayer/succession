# Privacy

Succession runs entirely on your machine. This page says what it reads,
what it writes and what it leaves alone.

## Summary

- No network calls. The plugin sends nothing and fetches nothing.
- No telemetry, analytics, account or server.
- It never reads the conversation transcript or chat history.
- Everything it writes goes into the `.succession/` folder of the project
  you are working in, as plain Markdown and JSON that you can read.

## What it reads

- **Files under `.succession/`** in your project.
- **Git objects in your repository**, through `git cat-file`,
  `git rev-parse` and `git merge-base`, to check the commit and file
  pointers in a handoff. It does not read your working tree to do this.
- **Its own charter template**, in the plugin folder, when a project has
  no charter yet.
- **How `.succession/` stands in git, at a close.** `git status` and
  `git check-ignore` are asked about that one folder, so that the close
  can end by telling you whether its files are committed. Nothing is
  staged or committed by the plugin.
- **Whether a `.git` entry exists in the project folder and the folders
  above it, and your repository's `.git/config`.** The session-start and
  prompt hooks find the
  repository root this way without starting git. The config is read for
  one thing: whether it names a work tree somewhere else. Nothing from it
  is stored or printed.
- **The prompt you submit, in memory, for one comparison.** Claude Code
  passes every submitted prompt to `UserPromptSubmit` hooks as JSON on
  standard input. `scripts/stand-down.sh` compares the prompt with the stop
  phrase (`Stand down, <codename>`) and exits. It does not write the prompt
  to disk, log it or pass it on. That JSON also carries the path of the
  session transcript; the script never opens it.

The session-start hook does not read its input at all when it prints the
status. Run a second time for the session's title, it looks through that
input for one thing: whether the session already has a title, in which
case it leaves the title alone. The hook that runs before a compaction
does not read its input. None of the three opens the transcript.

## What it writes

Under `.succession/` in your project:

- `seat.json` alone, holding a name and the time, at the first new
  session in a git project that has nothing of Succession yet: the
  plugin names the session by itself.
- `seat.json`, `lineage.jsonl` and `log.jsonl`: who held the seat and when,
  to the second; checkpoint summaries, verification verdicts, stand-downs,
  the time of each compaction of a session's context while the seat was
  held, and each tenure's one-line summary and last words. The summaries and
  last words are written by the model and passed to the script.
- `tenures/<NNN-codename>/verification.md`: the verifier's verdict.
- `tenures/<NNN-codename>/stood-down`: one line, left by a stand-down.
- `charter.md`: the plugin's template, written by a script when the
  project has none; after that, changed by the model when you ask.
- Each tenure's `checkpoints.md`, `handoff.md` and `lessons.md`: written
  by the model, following the plugin's skills, with whatever it knows
  about the work.

Read all of these before you share them, `log.jsonl` and `lineage.jsonl`
included: text a model wrote is in each. The log is never rewritten, so
a secret that lands in it stays until you deal with it; the README says
how, under "In a client's repository, or on a team".

Short-lived files, each gone when the write that made it ends:
`seat.json.tmp`, `charter.md.tmp`,
`tenures/<NNN-codename>/verification.md.tmp`, and the folders `.lock`
(holding one file, `pid`) and `.lock-clear`.

Nothing is written outside `.succession/`. A symbolic link at any path
the scripts read or write there is never followed: a link in the way of
a short-lived file is removed (the link itself, not what it points at),
and any other link, a linked `.succession/` or tenure folder included,
makes the script stop with "refusing to use a symbolic link". The
project's tests plant such links and check that files outside stay as
they were.

## What leaves your machine

Nothing, through this plugin. Two things are worth knowing all the same:

- If you commit `.succession/` to git and push it, its contents go wherever
  your repository goes.
- The model reads these files as part of your Claude Code session, the same
  as any other file in your project. At a session start the plugin itself
  hands Claude Code a few lines from them: the seat status, the
  officeholder's name (also as the session's title, which Claude Code
  keeps with the session) and the one-line summary of the last
  checkpoint. How Anthropic handles session data is
  covered by Anthropic's own terms and privacy policy, not by this plugin.

## Removing it

Delete the `.succession/` folder to remove every file the plugin has
written. Disable or uninstall the plugin with `/plugin`.
