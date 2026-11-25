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
  equipment = { [slot 1-19] = { id = <itemID>, enchant? = <id>, suffix? = <id> } },
  bags = { [bag 0-4] = { size = <n>, items = { [slot] = { id = <itemID>, count = <n> } } } },
  bank = { [-1, 5-10] = same shape as bags }, bankSeenAt = <unix s>,   -- only written while the bank is open
  quests = { captured = true, entries = { { id, title, level, complete?, failed?,
             objectives? = { { text, done, have?, need? } } } } },
  completedQuests = { <questID>, ... },                      -- sorted; absent when the client offers none
  talents = { { tree = "<name>", nodes = { { name, rank, max } } } },
  skills = { { name, rank, max, group = "<header>", profession? = true } },
  spells = { <spellID>, ... },                               -- the spellbook, sorted
  reputations = { { faction, standing = <1-8>, value, min, max } },
  recipes = { ["<profession>"] = { seenAt = <unix s>, entries = { { name, id? } } } },
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
