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

Each time the world map opens, the addon records where its own tab and panel and the client's own side tabs and
content inset really sit. It is data only (no chat, nothing sent); it reaches disk at the next client save.

```lua
WoWCompanionDB.observed.mapGeometry = {
  version = 1, t = <unix s>,
  tab = <frame>, panel = <frame>,          -- WoWCompanionMapTab, WoWCompanionMapPanel
  tabs = { <frame>, ... },                 -- the client's QuestsTab, EventsTab, MapLegendTab (those that exist)
  tabArt = { <frame>, ... },               -- our tab's textures (Background, Border, SelectedTexture, Icon, Highlight) and their extents
  tabOffset = <number>,                    -- the saved map tab offset below the frame's top (0 = default)
  questList = <frame>, questScroll = <frame>, -- the client's QuestMapFrame.QuestsFrame and its ScrollFrame, when present
  inset = <frame>,                         -- the client content-area inset the panel is anchored to
}
-- <frame> = { field, name, w, h, scale, shown, points = { { point, rel, relPoint, x, y }, ... } }
-- `rel` is the relative-to frame's name, or "(unnamed)"; sizes and offsets are rounded to 0.1.
```
