WoWCompanionPlan = {
  schema = "1.1", generated = 1795363900,
  characters = {
    ["Thrall"] = {
      zone = "Testisle",
      steps = {
        { n = 1, kind = "pickup", questID = 30, quest = "Quest 30", label = "Pick up Quest 30 from Elder Test", map = 7001, x = 50.0, y = 50.0 },
        { n = 2, kind = "objective", questID = 30, quest = "Quest 30", label = "Kill 5 wolves", map = 7001, x = 30.0, y = 20.0 },
        { n = 3, kind = "turnin", questID = 30, quest = "Quest 30", label = "Turn in Quest 30 to Elder Test", map = 7001, x = 50.0, y = 50.0, unlocks = { 31 } },
        { n = 4, kind = "pickup", questID = 31, quest = "Quest 31", label = "Pick up Quest 31 from Elder Test", map = 7001, x = 50.2, y = 50.0, locked = true, unlockedBy = { 30 }, depth = 1, chain = "Test Line" },
        { n = 5, kind = "turnin", questID = 31, quest = "Quest 31", label = "Turn in Quest 31 to Scout Test", map = 7001, x = 70.0, y = 40.0, locked = true, unlockedBy = { 30 }, depth = 1, chain = "Test Line", unlocks = { 32 } },
        { n = 6, kind = "pickup", questID = 32, quest = "Quest 32", label = "Pick up Quest 32 from Scout Test", map = 7001, x = 70.0, y = 40.0, locked = true, unlockedBy = { 31 }, depth = 2, chain = "Test Line" },
        { n = 7, kind = "pickup", questID = 40, quest = "Quest 40", label = "Pick up Quest 40 from Guard Test", map = 7001, x = 20.0, y = 20.0 },
        { n = 8, kind = "turnin", questID = 40, quest = "Quest 40", label = "Turn in Quest 40 to Guard Test", map = 7001, x = 20.0, y = 20.0, unlocks = { 50 } },
        { n = 9, kind = "pickup", questID = 50, quest = "Quest 50", label = "Pick up Quest 50 from Guard Test", map = 7001, x = 20.0, y = 20.0, locked = true, unlockedBy = { 30, 40 }, depth = 1, chain = "Guard Line" },
      },
    },
  },
}
