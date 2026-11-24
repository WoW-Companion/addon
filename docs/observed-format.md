# Quest observation log (`WoWCompanionDB.observed`)

A bounded ring of the player's own quest events, kept in the addon's SavedVariables. It leaves the game only when
the client saves (`/reload`, logout or quit); the addon never asks for a reload. Turn it off with "Keep a log of my
quest events for the overlay" in the Panel options.

```lua
WoWCompanionDB.observed = {
  version = 1,
  events = {  -- oldest first; at most 400, the oldest are dropped
    { t = <unix s>, ev = "accepted" | "turnedin" | "abandoned", questID = <n>, character = "<name>",
      map = <uiMapID>, x = <pct>, y = <pct>,      -- the player's position at the event (omitted when the client has none)
      npc = "<name>",                              -- accepted only, when the client names the giver
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
