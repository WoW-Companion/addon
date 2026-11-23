# Digest format (schema 1.4 and 2.0)

The companion writes advice into `WoWCompanion_Digest/Digest.lua`, a data-only
Lua file. The panel reads the global table `WoWCompanionDigest` and nothing else.

## Rules

- The file contains exactly one statement: `WoWCompanionDigest = { ... }`.
- Only literals: tables, strings, numbers, `true`/`false`. No functions, calls,
  variables or operators. `tests/slotcheck.lua` enforces this over the
  placeholder and the test fixtures.
- An absent or empty table (`WoWCompanionDigest = {}`) means "no advice yet".

## Fields

| Field | Type | Meaning |
| ----- | ---- | ------- |
| `schema` | number or string | Format version. This document is `"1.4"`. The panel accepts `1`, `"1.0"` to `"1.4"` and refuses any other major version. |
| `generated` | number | Unix time (seconds) the digest was computed. The panel shows its time and age ("advice from 11:23 (3 h ago)"); the time turns amber (with an explanatory tooltip) when the digest is older than 12 hours, and the panel notes when the character's last capture is more than 15 minutes newer than `generated` (a save right after a fresh digest does not count). |
| `build` | string | Game build it was computed for, e.g. `"1.60.0.64000"`. |
| `character` | string | Character name it is for. The panel refuses a digest for a different character. |
| `sections` | list | Ordered list of sections, shown in this order. |
| `dungeons` | list | Optional, schema 1.2. At most 3 entries, each `{ name = "<dungeon>", line = "<= 60 chars: level fit and top upgrade>", item_id = <number or nil> }`. |
| `talents` | list | Optional, schema 1.2. At most 3 entries, each `{ line = "<= 60 chars: next talent point>", spell_id = <number or nil> }`. |

Each section is `{ id = "<id>", lines = { <line>, ... } }`. Known ids:
`next_quests`, `upgrades`, `keep_materials`, `notes` (free-form). Unknown ids
are ignored.

Each line is `{ text = "short line", item = <item id>, quest = <quest id> }`.
`text` is required; `item` and `quest` are optional numbers. A line with an `item` shows that item's tooltip on mouseover (display only). Files without `item` render as before.

### Schema 1.4: details, prompts and training

Schema 1.4 adds two optional fields to every `next_quests` and `upgrades` line and to `dungeons` and `talents` entries: `details` (a list of 1 to 4 short strings, shown as the first rows of the entry's detail card) and `prompt` (a ready question of at most 500 characters, pre-filled in the card's ask box). Without them the card falls back to the `ASK_ABOUT_*` templates and shows only what the client knows live.

`next_quests` may hold a `kind = "training"` line: `text`, `level`, `spells = { { id, name, rank (only when ranked), new (false for an upgrade of a known rank) }, ... }`, and optionally `npc`, `zone`, `x`, `y`. The panel shows `New at level 10: Charge (Rank 2), Thunder Clap` with the class icon, drops spells the client reports as known, and hides the entry when none is left. The talent entry's card shows the first `talents` entry as the plan's next pick (its `prompt` is used when the talent line has none).

Clicking a quest in the log opens it in the client's quest log; any other entry (and a right-click on any entry) opens its detail card. **Send** queues the box through the ask queue (`docs/ask-format.md`); **Copy** selects the text for Ctrl+C. The panel accepts every `1.x`, so older digests keep working with the template prompts.

### Schema 1.3: structured lines

Schema 1.3 adds optional fields to the lines, so the panel can lay them out like a quest tracker. `text` and `quest` are unchanged, so older addons keep working, and a line without these fields (a schema 1.2 digest) renders its `text` in the new style without the level and objective rows. Every field is optional and omitted when unknown; strings are data-only Lua literals and are never truncated (only `text` keeps its 60 character cap).

`next_quests` lines:

| Field | Type | Meaning |
| ----- | ---- | ------- |
| `kind` | string | `"pickup"`, `"turnin"`, `"progress"`, `"talent"` or `"note"`. The panel lays out the first three as quest entries; `"talent"` as the talent entry. |
| `title` | string | The full quest title. |
| `level` | number | The quest level; the title shows as `[level] Title`, coloured by difficulty against the player's level. |
| `class` | boolean | `true` for class quests: ` (Class)` follows the title. |
| `elite` | boolean | `true` for elite or group quests: a dim `(Elite)` is shown right-aligned. |
| `npc` | string | The giver of a pick-up (`Pick up from <npc>`) or the turn-in NPC (`Turn in to <npc>`). |
| `zone` | string | The zone name; a pick-up names it only when it is not the player's current zone. |
| `objectives` | list | `{ text = "...", have = 0, need = 6 }` per objective, optional ones included (an optional objective's text ends `(Optional)`, or it carries `optional = true`). Shown as indented `have/need text` lines. |
| `points` | number | Unspent talent points, for the `"talent"` line. |

`upgrades` lines add `slot` (string), `ilvl` and `atLevel` (numbers) beside `text` and `item`; the panel shows `atLevel` dim under the item. Schema 1.7 adds `wear` ("Wear now" or "From level 12"), `gain` ("Big upgrade", "Solid upgrade", "Small upgrade"), `replaces`, `how` (one line), `pathKind` (`quest`, `craft`, `auction`, `dungeon` or `creature`, for the path icon) and optionally `materials = { { name, have, need } }`. With them the panel and the upgrades chip show `<Slot>: <Item> — <gain>` over the path icon and `how`; without them just `<Slot>: <Item>`. `ilvl` is never shown.

While a quest is in the log the panel uses the client's live title, level and objectives instead of the stored ones (a quest turned in drops off, a finished one shows `Ready to turn in`). The panel also collapses each quest and each section; the choice is saved per quest id.

The panel shows `dungeons` and `talents` as "Dungeons" and "Talents" sections, after the others and only when present. A `dungeons` entry with `item_id` shows that item's tooltip on mouseover, and a `talents` entry with `spell_id` shows that spell's tooltip (display only). Both sections collapse, and the settings page can hide them. Readers that only know schema 1.0 or 1.1 ignore the unknown keys.

## Schema 2.0: one digest per character

A schema 2.0 file holds one schema 1.2 digest for each character, so alts share one file:

```lua
WoWCompanionDigest = {
  schema = "2.0",
  generated = 1800000000,
  characters = {
    ["Testchar"] = { schema = "1.2", generated = 1800000000, character = "Testchar", sections = { ... } },
    ["Otherchar"] = { schema = "1.2", ... },
  },
}
```

- Keys are the character name exactly as `UnitName("player")` returns it; the realm is not part of the key.
- Each value is a complete schema 1.x digest (with its own `character`, `generated` and `sections`), with its own `schema` (e.g. `"1.3"`) kept inside.
- The panel, the Next up line, `/wowc status`, the stale hint and the button tooltip read `characters[UnitName("player")]`, then a case-insensitive match. The panel accepts `"2"` and `"2.x"` and refuses other major versions.
- With no entry for the character (or a schema 1 file written for another character) the panel shows the three steps to get one, and for a 2.0 file lists up to 5 characters that do have digests. The Next up line says "No digest for <name>".
- The data-only rules apply to the nested tables too: only literals, no calls, functions or operators. `["Name"] = {` keys are literal strings.

## Example (schema 1.3)

```lua
WoWCompanionDigest = {
  schema = "1.3",
  generated = 1800000000,
  build = "1.60.0.64000",
  character = "Thrall",
  sections = {
    { id = "next_quests", lines = {
      { text = "Turn in The Hungry Ettin", quest = 1234, kind = "turnin", title = "The Hungry Ettin", level = 9, npc = "Marshal Dughan" },
      { text = "Blood Tithe: 0/1 Find Aamelia Windfield", quest = 1235, kind = "progress", title = "Blood Tithe", level = 9,
        objectives = { { text = "Find Aamelia Windfield", have = 0, need = 1 } } },
    } },
    { id = "upgrades", lines = {
      { text = "Equip Hammer of Fate", item = 5678 },
    } },
  },
  dungeons = {
    { name = "Deadmines", line = "Level fit 15-20; top upgrade: Cookie's Stirring Rod", item_id = 5198 },
  },
  talents = {
    { line = "Next point: Mortal Strike", spell_id = 12294 },
  },
}
```

## Changing the format

Any incompatible change bumps `schema`; the panel only renders versions it knows.

## Schema 1.5 additions (all optional)

On any digest entry (a line of a section, a talent, a dungeon): `asks` (1-3 natural questions, at most 90 characters each, shown as clickable chips on the card), `ref` (a reference string sent back with each question asked from that entry). A note line may carry `kind = "giver"` with `npc`, `zone`, `x`, `y`, `quest` and `title`: the panel shows the client's "!" quest icon and its card offers "Show on map" when the plan has a step for `quest`.

## Schema 1.6 additions (all optional)

On any digest entry: `why`, a short factual reason the entry is worth doing (at most 70 characters). The panel shows it as one dim line under the entry (at most 2 lines; the "Show why each entry matters" option hides it), the card shows it as its first detail line, and the map plan uses it as a row's sub-line when the row has no objective progress to show. Plan steps carry plain labels ("Pick up …", "Kill … (0/1)", "Collect … (0/8)", "Turn in …"), shown as they are.
