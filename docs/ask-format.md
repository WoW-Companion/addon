# Ask format (schema 1)

`/ask <question>` (or `/wowc ask <question>`) queues a question in SavedVariables.
The companion reads the queue from `WoWCompanion.lua` in `WTF/.../SavedVariables`
after `/reload` or logout, and writes answers into `WoWCompanion_Answers/Answers.lua`.
The addon never sends anything itself; a question only leaves the game through
SavedVariables.

## Questions: `WoWCompanionDB.asks`

A list, oldest first, capped at 10 entries (the oldest is dropped). Each entry:

| Field | Type | Meaning |
| ----- | ---- | ------- |
| `id` | string | Unique per character: `"<asked_at>-<n>"`, where `n` counts up in `WoWCompanionDB.ask_seq`. Answers are keyed by it. |
| `asked_at` | number | Unix time (seconds) the question was asked. |
| `character` | string | Character name that asked. |
| `text` | string | The question, trimmed and cut to 500 characters. Stored as plain data, never executed. |
| `answered` | boolean | Set to `true` by the addon once a matching answer is loaded. |
| `answered_at` | number | Unix time of the matching answer (set with `answered`). |

An empty question is not queued. The panel shows an unanswered question as
"queued; /reload to send".

## Answers: `WoWCompanion_Answers/Answers.lua`

A data-only, load-on-demand slot addon (`## LoadOnDemand: 1`). The panel loads it with
`C_AddOns.LoadAddOn` (falling back to `LoadAddOn`) each time it opens.

- The file contains exactly one statement: `WoWCompanionAnswers = { ... }`, of literals only
  (no functions, calls, variables or operators). `tests/slotcheck.lua` enforces this.
- `WoWCompanionAnswers = {}` means "no answers yet".

| Field | Type | Meaning |
| ----- | ---- | ------- |
| `schema` | number | Format version. This document is `1`; any other value is ignored with a panel note. |
| `answers` | table | Keyed by question `id` (string). |

Each answer is `{ answered_at = <unix time>, text = "answer", sources = { "source", ... } }`.
`answered_at` and `text` are required; `sources` is optional and shown as a "sources:" line.
An entry missing either required field is ignored and the panel notes how many were. Answers
for ids not in the queue are ignored.

## Example

```lua
WoWCompanionAnswers = {
  schema = 1,
  answers = {
    ["1799999000-1"] = {
      answered_at = 1799999900,
      text = "Do the Hungry Ettin turn-in first.",
      sources = { "Quest 1234" },
    },
  },
}
```

## Changing the format

Any incompatible change bumps `schema`; the panel only reads versions it knows.
