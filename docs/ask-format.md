# Ask format (schema 1)

**The in-game ask queue was removed in 0.6.6.** The addon no longer has `/ask` or `/wowc ask`, never writes
`WoWCompanionDB.asks`, and ships no Send path; copy and paste into the overlay is the way to ask. Data an earlier
version already wrote to `WoWCompanionDB.asks` is left as it was. The format below is kept for reading that data.

`/ask <question>` (the removed command) queued a question in SavedVariables.
The companion read the queue from `WoWCompanion.lua` in `WTF/.../SavedVariables`
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

Left-clicking a non-quest entry, or right-clicking any entry, opens a card beside the panel. Under the plain label "Ask the companion" (hidden when the entry has no questions) it shows the entry's `asks` (digest schema 1.5: 1-3 questions of at most 90 characters) as clickable chips; an older digest gets up to 2 questions built from the entry's own fields ("What's <title> for?", "Where should my talent point go?"...), never a digest line verbatim and never a question built from a section summary (the upgrade set and the Stats card ask only what the digest gave). Clicking a chip opens a copy box directly under it, with the question selected and focused and a "Ctrl+C" hint. Addons cannot write the clipboard, so the player's own Ctrl+C copies it; the key handler changes nothing, and on a following frame the card says "Copied. Paste it into the overlay with Ctrl+V." Nothing is queued or written. A dim line reads "Or ask anything in the overlay."

## Clearing old questions (0.6.28)

On login the addon drops entries of `WoWCompanionDB.asks` that are older than 24 hours, and any whose `id` is
listed in the digest's optional top-level `answered_asks` (a list of id strings; no digest writer emits it yet).
`/wowc status` then reads "Questions waiting for the app: N (oldest <age>)", and prints nothing when N is 0.
