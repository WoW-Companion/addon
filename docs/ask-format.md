# Ask format (schema 1)

`/ask <question>` (or `/wowc ask <question>`) queues a question in SavedVariables.
The companion reads the queue from `WoWCompanion.lua` in `WTF/.../SavedVariables`
after `/reload` or logout, and the overlay answers it there; the addon shows no answers (the old `WoWCompanion_Answers` slot was removed in 0.2.0).
The addon never sends anything itself; a question only leaves the game through
SavedVariables.

## Questions: `WoWCompanionDB.asks`

A list, oldest first, capped at 10 entries (the oldest is dropped). Each entry:

| Field | Type | Meaning |
| ----- | ---- | ------- |
| `id` | string | Unique per character: `"<asked_at>-<n>"`, where `n` counts up in `WoWCompanionDB.ask_seq`. |
| `asked_at` | number | Unix time (seconds) the question was asked. |
| `character` | string | Character name that asked. |
| `text` | string | The question, trimmed and cut to 500 characters. Stored as plain data, never executed. |
| `answered` | boolean | Legacy (0.1.x): no longer set by the addon. |
| `answered_at` | number | Legacy (0.1.x): no longer set by the addon. |

An empty question is not queued. Right-click "Ask about this" on a panel line queues the same way, and
both print: "Queued for WoW Companion. /reload and the overlay will answer it."

## Detail card

Left-clicking a non-quest entry, or right-clicking any entry, opens a card beside the panel with a box holding the entry's `prompt` (or the template above). **Send** queues the box text exactly like `/ask` (one question, cut to 500 characters) and the card remembers the ask id in `WoWCompanionDB.cardAsks[<entry key>]`. **Copy** focuses and selects the text; the player presses Ctrl+C and pastes into the overlay's Ask box (addons cannot write the clipboard).

## Answers file (optional)

When the companion writes `WoWCompanion_Answers/Answers.lua`, a data-only file holding one statement, `WoWCompanionAnswers = { answers = { { id = "<ask id>", question = "<text>", text = "<answer>" }, ... } }`, the card shows the answer to the question sent from that entry (matched by `id`, or by the `question` text) under the prompt. The addon only reads it; nothing in the repo ships that folder.
