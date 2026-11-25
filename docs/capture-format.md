# Character capture (`WoWCompanionDB.characters`)

The addon records the player's own character so the WoW Companion app can read it. It is our own schema, built
only from the client's documented read APIs. Nothing is sent; the data leaves the game only when the client saves
(`/reload`, logout or quit) and the addon never asks for one. Turn it off with "Record my character for the WoW
Companion app" in the Panel options: off means nothing is captured (what was saved earlier stays until you
reset the addon's data).

Schema version: **1** (`version` on each record). Fields are only added within a version.

```lua
WoWCompanionDB.characters["<realm>:<name>"] = {
  version = 1, name, realm, capturedAt = <unix s>,           -- capturedAt: the last time any part was read
  level, class = "<token>", race = "<token>", faction = "Horde" | "Alliance",
  client = { version = "<x.y.z>", build = "<n>" },
  money = <copper>, xp, xpMax, rested,
  location = { map = <uiMapID>, x = <pct 0-100>, y = <pct> }, hearth = "<bind location name>",
  equipment = { [slot 1-19] = { id = <itemID>, enchant? = <id>, suffix? = <id>, quality? = <0-8>, ilvl? = <n>, reqLevel? = <n>, equipLoc? = "INVTYPE_…" } },
  bags = { [bag 0-4] = { size = <n>, items = { [slot] = { id = <itemID>, count = <n>, enchant? , suffix? , quality? , ilvl? , reqLevel? , equipLoc? } } } },   -- item info fields are left out until the client has cached the item
  bank = { [-1, 5-10] = same shape as bags }, bankSeenAt = <unix s>,   -- only written while the bank is open
  quests = { captured = true, entries = { { id, title, level, complete?, failed?,
             objectives? = { { text, done, have?, need? } } } } },
  completedQuests = { <questID>, ... },                      -- sorted; absent when the client offers none
  talents = { { tree = "<name>", points = <spent>, nodes = { { node, entry, spell, name, rank, max, posX, posY } } } },
  talentPoints = <unspent talent points>,                    -- absent when no API gave a number
  apiProbe = { seenAt, talents = { legacy, traits, specialization, legacyNodes, traitsNodes, named, withSpell, used }, points = { ... },
    spells = { modern, classic, links, used, isSpellKnown } },  -- per path: item count, -1 = API missing; no values
  skills = { { name, rank, max, group = "<header>", profession? = true } },
  stats = { seenAt, level,                                     -- what the client reports; a missing API leaves its key out
    stats = { str|agi|sta|int|spi = { base, total, pos, neg } },  -- UnitStat: "Intellect 90 (50+40)" is base 50, pos 40, total 90
    healthMax, manaMax, armor, meleeCrit, rangedCrit, dodge, parry, block,   -- percent for the chances
    spellCrit = { max, schools = { [2..7] = pct } }, manaRegen = { base, casting }, attackPower, rangedAttackPower,
    spellBonus = { damage (best school), healing },
    perPoint = { spellCritFromInt, critFromAgi, manaRegenFromSpi, healthRegenFromSpi } },  -- the client's own per-point getters only
  spells = { <spellID>, ... },                               -- the spellbook, sorted
  reputations = { { faction, standing = <1-8>, value, min, max } },
  recipes = { ["<profession>"] = { seenAt = <unix s>, entries = { { name, id?, item?, difficulty? = "orange"|"yellow"|"green"|"grey",
    makes? = { item, count }, reagents? = { { item, count } }  --[[ at most 8 ]], learnSkill? = <skill needed, when exposed> } } } },
}
```

Notes:

- Items and spells are ids, never links; no tooltips are scanned.
- The bank is read only while the bank window is open; otherwise the last snapshot and its `bankSeenAt` stay.
- Recipes come from the trade skill (or craft) window when the player opens it, kept per profession; `id` is
  the spell or item id in the recipe's link.
- Quests, skills and reputations in a header the player collapsed in the client's own window may be missing: reading
  them would mean expanding that window, which the addon does not do.
- Reads wait about two seconds so a burst of events is read once, and are held back while in combat; they run when
  combat ends.
- `profession` marks the skills under the client's Professions and Secondary Skills headers.
- Skills are read with `C_SkillInfo.GetNumSkillLines` and `C_SkillInfo.GetSkillLineInfo` (a table per line) when the client has them,
  else with the legacy `GetNumSkillLines`/`GetSkillLineInfo`. They refresh on `SKILL_LINES_CHANGED`, at login and on level up; an open
  profession window also records `C_TradeSkillUI.GetBaseProfessionInfo()`'s skill level and max for that profession.

## Client APIs used (all read-only)

UnitName, GetRealmName, UnitLevel, UnitClass, UnitRace, UnitFactionGroup, GetBuildInfo, GetMoney, UnitXP,
UnitXPMax, GetXPExhaustion, C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition, GetBindLocation,
GetInventoryItemID, GetInventoryItemLink, C_Container.GetContainerNumSlots / GetContainerItemInfo (or the older
GetContainerNumSlots, GetContainerItemID, GetContainerItemInfo), GetNumQuestLogEntries, GetQuestLogTitle
(or C_QuestLog.GetInfo and IsComplete), GetNumQuestLeaderBoards, GetQuestLogLeaderBoard, GetQuestsCompleted (or
C_QuestLog.GetAllCompletedQuestIDs), GetNumTalentTabs, GetTalentTabInfo, GetNumTalents, GetTalentInfo,
GetNumSkillLines, GetSkillLineInfo, GetNumSpellTabs, GetSpellTabInfo, GetSpellLink (or
C_SpellBook.GetSpellBookItemInfo), GetNumFactions, GetFactionInfo, IsTradeSkillLinked, GetTradeSkillLine,
GetNumTradeSkills, GetTradeSkillInfo, GetTradeSkillItemLink, GetCraftDisplaySkillLine, GetCraftName, GetNumCrafts,
GetCraftInfo, GetCraftItemLink, InCombatLockdown. `tests/guard.lua` lists them and fails on any other client API
called in `Capture.lua`.

## characters[<key>].flightPoints

Written when the flight map opens (read-only, never travels): the character's known flight points.

```
flightPoints = { seenAt = <unix s>, relative = true | nil,
  nodes = { { id = <node id>, name = "<flight point>", map = <uiMapID of the continent>,
              x = <0-100>, y = <0-100>, state = "current" | "reachable",
              zoneMap = <uiMapID of the node's own zone>, zoneX = <0-100>, zoneY = <0-100> }, ... } }   -- at most 80
```

Unknown and "distant" (unreachable) nodes are skipped. Opening the map again replaces the list. `map`, `x`, `y` are on the continent map (the player's zone's `C_Map.GetMapInfo(id).parentMapID` chain up to `Enum.UIMapType.Continent`); `zoneMap/zoneX/zoneY` come from `C_Map.GetMapInfoAtPosition`, `GetWorldPosFromMapPos`, `GetMapPosFromWorldPos` and are absent when the client lacks them. `relative = true` means no continent was found (or a position fell outside 0-100), so positions are relative to the zone the map was queried with; the classic `TaxiNodePosition` is relative to the map the flight window shows, so classic records are marked this way unless a continent is found. Source: `C_TaxiMap.GetAllTaxiNodes(uiMapID)` where the client has it, else `NumTaxiNodes`, `TaxiNodeName`, `TaxiNodeGetType`, `TaxiNodePosition`.
