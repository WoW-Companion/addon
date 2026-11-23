# Ask format (schema 1)

`/ask <question>` (or `/wowc ask <question>`) queues a question in SavedVariables.
The companion reads the queue from `WoWCompanion.lua` in `WTF/.../SavedVariables`
whenever the game saves (logout, quit or a UI reload), and the overlay answers it there; the addon shows no answers (the old `WoWCompanion_Answers` slot was removed in 0.2.0).
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
| `ref` | string | Optional. The digest entry's `ref` (at most 120 characters), so the overlay files the answer under that entry. Absent for `/ask` and for entries with no `ref`. |
| `answered` | boolean | Legacy (0.1.x): no longer set by the addon. |
| `answered_at` | number | Legacy (0.1.x): no longer set by the addon. |

An empty question is not queued. Right-click "Ask about this" on a panel line queues the same way, and
both print: "Queued for WoW Companion. The overlay answers it after the game's next save."

## Detail card

Left-clicking a non-quest entry, or right-clicking any entry, opens a card beside the panel. Under "Ask the companion" it shows the entry's `asks` (digest schema 1.5: 1-3 questions of at most 90 characters) as clickable chips; an older digest gets up to 2 questions built from the entry's own fields ("What's <title> for?", "Where should my talent point go?"...), never a digest line verbatim. Clicking a chip queues that question exactly like `/ask`, adding the entry's `ref`, and the card remembers the ask id in `WoWCompanionDB.cardAsks[<entry key>]`. The status line reads "Asked. The answer appears in the overlay. The same questions are one click away there too." The question also sits selected in a small box with a **Copy** button and a "Ctrl+C" hint; after Ctrl+C the card shows "Copied" for 1.5 s and lets go of the selection (addons cannot write the clipboard). "Type your own..." opens a one-line box; Enter queues the typed question with the entry's `ref`.

## Answers file (optional)

When the companion writes `WoWCompanion_Answers/Answers.lua`, a data-only file holding one statement, `WoWCompanionAnswers = { answers = { { id = "<ask id>", question = "<text>", text = "<answer>" }, ... } }`, the card shows the answer to the question sent from that entry (matched by `id`, or by the `question` text) under the prompt. The addon only reads it; nothing in the repo ships that folder.
