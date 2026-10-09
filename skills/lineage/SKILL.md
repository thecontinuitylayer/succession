---
name: lineage
description: Show every officeholder this project has had, with name, number, dates, how each tenure ended, what it did and its last words. Use when the owner asks for the lineage, the succession history or who has held the seat.
---

# Show the lineage

Read `.succession/lineage.jsonl`, `.succession/seat.json` and
`.succession/log.jsonl`. Change nothing. If there is no `.succession` folder, say that no officeholder has
been seated in this project yet and stop.

`lineage.jsonl` holds one JSON object per line. An officeholder has a
`"event":"seated"` line and, once the tenure has ended, a
`"event":"closed"` line with `how`, `summary` and `last_words`.

Show this and nothing more:

```markdown
**Seat:** <vacant | occupied by Name-NNN since ... | Name-NNN stood down, not yet closed>

| No. | Name | Seated (UTC) | Left (UTC) | Ended by | What it did | Last words |
| --- | --- | --- | --- | --- | --- | --- |
| 001 | Sextant | 2026-10-07 14:02 | 2026-10-07 18:40 | handoff | ... | "..." |

Latest handoff: <path>. Verdict: <the verdict of the last "type":"verify" line for that tenure in .succession/log.jsonl, or "not verified yet">
```

Rules:

- One row per number, oldest at the top.
- "Ended by": `close` is "handoff", `stand_down` is "stood down, handoff",
  `vacate` is "no handoff", and an officeholder still seated is "in the
  seat".
- Take "What it did" and "Last words" from the file as written. Do not
  improve them. Shorten a long one with an ellipsis so that each row stays
  on one line.
- Keep the table narrow enough to fit a screenshot.
