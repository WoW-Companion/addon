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
