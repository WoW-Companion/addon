# Digest format (schema 1.3 and 2.0)

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
| `schema` | number or string | Format version. This document is `"1.3"`. The panel accepts `1`, `"1.0"`, `"1.1"`, `"1.2"` and `"1.3"` and refuses any other major version. |
| `generated` | number | Unix time (seconds) the digest was computed. The panel shows its time and age ("advice from 11:23 (3 h ago)"); the panel adds a note to refresh the digest and `/reload` only when the digest is older than 12 hours, or the character's last capture is more than 15 minutes newer than `generated` (a `/reload` right after a fresh digest does not count). |
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

`upgrades` lines add `slot` (string), `ilvl` and `atLevel` (numbers) beside `text` and `item`; the panel shows them dim under the item.

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
