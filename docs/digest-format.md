# Digest format (schema 1.2 and 2.0)

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
| `schema` | number or string | Format version. This document is `"1.2"`. The panel accepts `1`, `"1.0"`, `"1.1"` and `"1.2"` and refuses any other major version. |
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
- Each value is a complete schema 1.2 digest (with its own `character`, `generated` and `sections`), with `schema = "1.2"` kept inside.
- The panel, the Next up line, `/wowc status`, the stale hint and the button tooltip read `characters[UnitName("player")]`, then a case-insensitive match. The panel accepts `"2"` and `"2.x"` and refuses other major versions.
- With no entry for the character (or a schema 1 file written for another character) the panel shows the three steps to get one, and for a 2.0 file lists up to 5 characters that do have digests. The Next up line says "No digest for <name>".
- The data-only rules apply to the nested tables too: only literals, no calls, functions or operators. `["Name"] = {` keys are literal strings.

## Example (schema 1.2)

```lua
WoWCompanionDigest = {
  schema = "1.2",
  generated = 1800000000,
  build = "1.60.0.64000",
  character = "Thrall",
  sections = {
    { id = "next_quests", lines = {
      { text = "Turn in The Hungry Ettin", quest = 1234 },
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
