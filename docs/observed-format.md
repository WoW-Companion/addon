# Observation log (`WoWCompanionDB.observed`)

A bounded record of the player's own quest events and of what the player sees: trainers, vendors, gathering and fishing, kept in the addon's SavedVariables. It leaves the game only when
the client saves (`/reload`, logout or quit); the addon never asks for a reload. Turn it off with "Keep a log of my
quest events, trainers, vendors and gathering for the overlay" in the Panel options (on by default; off records nothing). Strictly read-only: the client's read APIs only, no tooltip scanning, nothing bought, learned or clicked, and work waits until the player is out of combat.

```lua
WoWCompanionDB.observed = {
  version = 2,
  events = {  -- oldest first; at most 400, the oldest are dropped
    { t = <unix s>, ev = "accepted" | "turnedin" | "abandoned", questID = <n>, character = "<name>",
      map = <uiMapID>, x = <pct>, y = <pct>,      -- the player's position at the event (omitted when the client has none)
      npc = "<name>",                              -- accepted only, when the client names the giver
      npcId = <n>, npcMap = <uiMapID>, npcX = <pct>, npcY = <pct>, -- accepted only: the giver's creature id and the player's position at the dialog
      offPlan = true },                            -- accepted only: the quest was not in the plan
  },
}
```

A removal that follows a turn-in is not an abandon; an abandon is logged about a second after the quest leaves the log.

## Map geometry (`WoWCompanionDB.observed.mapGeometry`)

Each time the world map opens, the addon records where its own round button and plan and the client's own quest list
really sit. It is data only (no chat, nothing sent); it reaches disk at the next client save.

```lua
WoWCompanionDB.observed.mapGeometry = {
  version = 1, t = <unix s>,
  panel = <frame>,                         -- WoWCompanionMapPanel (our plan)
  questList = <frame>, questScroll = <frame>, -- the client's QuestMapFrame.QuestsFrame and its ScrollFrame, when present
  inset = <frame>,                         -- the client content-area inset around the quest list
  control = "round",                       -- the map control: always the round map button
  round = <frame> + { level, strata, slot }, -- WoWCompanionMapRoundButton (slot 1 = the top of the column of round map buttons)
  slots = { { x, y, w, h }, ... },         -- the round buttons found already in that column (rectangles from the container's top-left corner)
  sizeMode = "small" | "full",             -- the world map's size mode
  sidePanel = { open, weOpened, planSelected, deferred }, -- the quest-log side panel's state, and whether we opened it
  roundButton = { shown, visible, rect = { l, b, w, h }, strata, level, parent, slot, t }, -- the round button's state
  planTab = { rect, shown, visible, anchor = "toggle" | "fallback", toggleRect, overlaysOn }, -- our lower-right plan tab, the client's quest-pane toggle's rectangle, and whether our map overlays are on
  planRect = { l, b, w, h }, questScrollRect = { l, b, w, h }, insetRect = { l, b, w, h }, -- our plan's rectangle, the client quest list's, and the inset's (absent until laid out)
  scrollTemplate = <string>,               -- the scroll frame template our plan's scroll bar comes from
}
-- <frame> = { field, name, w, h, scale, shown, points = { { point, rel, relPoint, x, y }, ... } }
-- `rel` is the relative-to frame's name, or "(unnamed)"; sizes and offsets are rounded to 0.1.
```

## What the player sees (`observed.trainers`, `observed.vendors`, `observed.gathering`)

Sections are lists, oldest first; a full section drops its oldest entries. `x`/`y` are the player's own map position
in percent (the npc stands within a few yards) rounded to 0.1.

```lua
observed.trainers = {  -- at most 300 trainers; opening a trainer again replaces its record
  { npc = <creature id>, name = "<name>", map = <uiMapID>, x, y, reaction = <1..8>, faction = "Alliance" | "Horde",
    t = <unix s>,
    offers = {         -- at most 200 per trainer: class and profession trainers alike
      { name = "<service>", rank = "<subtext>", state = "available" | "unavailable" | "used",
        cost = <copper>, level = <required level>, icon = <file id>,
        skill = "<profession>", skillLevel = <n>,                     -- the skill gate, when there is one
        spell = <spell id> },                                         -- when the client links one
    } },
}
observed.vendors = {   -- at most 300 vendors; opening a vendor again overwrites its stock
  { npc, name, map, x, y, reaction, faction, t,
    items = { { id = <item id>, price = <copper>, stack = <n>, limited = <n left, only when limited>, ext = <true | { { id = <item id>, count = <n> } | { currency = <currency id>, count = <n> }, ... }> --[[ also costs items or currency: the list (at most 8) when the client gives the cost rows, else true ]] } } },  -- at most 200
}
observed.flightmasters = {  -- at most 300; the flight master's npc only, never the node list; opening again replaces
  { npc, name, map, x, y, reaction, faction, t },
}
-- A character's known flight points are not here: they are in the capture, characters[<key>].flightPoints (docs/capture-format.md): positions on the continent map plus each node's own zone map and x, y.
observed.raw = {      -- the first 3 raw return tuples per window kind per session, to verify the field mapping; temporary
  trainer = { { call = "GetTrainerServiceInfo", n = <values returned>, t = <unix s>, vals = { ... } } },
  errors = { { kind = "<window>", t = <unix s>, msg = "<cut to 120>" } },  -- the last 5 failed reads
  merchant = { ... }, tradeskill = { ... },   -- strings cut to 60 characters, at most 12 values
}
observed.gathering = { -- at most 2000 rows, aggregated; no raw events. The least recently updated row is dropped first
  { kind = "herb" | "mine" | "skin" | "fish", source = "<name>" | nil,  -- skinning: the target's name; nodes and schools: not exposed
    map = <uiMapID>, cx = <n>, cy = <n>,        -- the cell: floor(percent / 5)
    n = <loots>, t = <unix s>, skillMin = <n>, skillMax = <n>,           -- the player's skill in the profession
    items = { [<item id>] = { count = <total>, n = <loots with it> } } },  -- at most 40 per row
}
```

Gathering is recorded only for loot that opens right after the player's own Herb Gathering, Mining, Skinning or
Fishing cast (within 20 s, 45 s for Fishing); any other loot is ignored.

Windows are read about 0.5 s after they open and 1.5 s after an update (the lists can arrive late); the old window
event or `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` opens a window, once. A secret value (the client's `issecretvalue`)
is never saved: every stored value is a string, number or boolean.

## Character stats (`characters[<realm:name>].stats`)

What the client reports about the character, read on login, level up, equipment change and talent change
(coalesced, never in combat). The shape is in `capture-format.md`. Every value goes through `WC.Clean` and a
number the client does not return is left out. Read-only APIs used (interface 16001): `UnitStat`,
`UnitHealthMax`, `UnitPowerMax`, `UnitArmor`, `GetSpellCritChance`, `GetCritChance`, `GetRangedCritChance`,
`GetDodgeChance`, `GetParryChance`, `GetBlockChance`, `GetManaRegen`, `UnitAttackPower`,
`UnitRangedAttackPower`, `GetSpellBonusDamage`, `GetSpellBonusHealing`, and the per-point getters
`GetSpellCritChanceFromIntellect`, `GetCritChanceFromAgility`, `GetUnitManaRegenRateFromSpirit`,
`GetUnitHealthRegenRateFromSpirit`. The client exposes no getter for mana or health per point, so those are not stored.
`UnitStat`'s first return is the effective total here, so `base` is stored as `total - pos - neg` (`neg` is reported negative), matching the tooltip "90 (50+40)".
The per-point getters do not exist on interface 16001, so `perPoint` is normally absent: consumers must not rely on it.
