# Digest format (schema 1)

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
| `schema` | number | Format version. This document is `1`. The panel refuses any other value. |
| `generated` | number | Unix time (seconds) the digest was computed. The panel shows its age ("updated 3 h ago"); older than 12 hours it adds a note to refresh the digest and `/reload`. |
| `build` | string | Game build it was computed for, e.g. `"1.60.0.64000"`. |
| `character` | string | Character name it is for. The panel refuses a digest for a different character. |
| `sections` | list | Ordered list of sections, shown in this order. |

Each section is `{ id = "<id>", lines = { <line>, ... } }`. Known ids:
`next_quests`, `upgrades`, `keep_materials`, `notes` (free-form). Unknown ids
are ignored.

Each line is `{ text = "short line", item = <item id>, quest = <quest id> }`.
`text` is required; `item` and `quest` are optional numbers. A line with an `item` shows that item's tooltip on mouseover (display only). Files without `item` render as before; the format stays schema 1.

## Example

```lua
WoWCompanionDigest = {
  schema = 1,
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
}
```

## Changing the format

Any incompatible change bumps `schema`; the panel only renders versions it knows.
