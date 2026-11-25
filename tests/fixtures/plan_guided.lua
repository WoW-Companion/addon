WoWCompanionPlan = {
  schema = "1.2", generated = 1795363809,
  characters = {
    ["Thrall"] = {
      zone = "Testisle",
      steps = {
        { n = 1, kind = "pickup", questID = 10, quest = "Quest 10", label = "Pick up Quest 10", map = 7001, x = 50.0, y = 50.0 },
        { n = 2, kind = "objective", questID = 10, quest = "Quest 10", label = "Kill Test Wolf", map = 7001, x = 60.0, y = 50.0 },
        { n = 3, kind = "turnin", questID = 10, quest = "Quest 10", label = "Turn in Quest 10", map = 7001, x = 50.0, y = 50.0 },
        { n = 4, kind = "pickup", questID = 20, quest = "Quest 20", label = "Pick up Quest 20", map = 7001, x = 20.0, y = 20.0 },
      },
      guidance = {
        [10] = { questID = 10, quest = "Quest 10", steps = { 1, 2, 3 },
          objectives = { { text = "Kill Test Wolf", map = 7001, x = 60.0, y = 50.0 }, { text = "Collect Test Shield", map = 7001, x = 70.0, y = 40.0 } },
          turnin = { text = "Turn in Quest 10 to Elder Test", map = 7001, x = 50.0, y = 50.0 } },
        [30] = { questID = 30, quest = "Quest 30", class = true, steps = {},
          objectives = { { text = "Slay Test Drake", map = 7001, x = 80.0, y = 80.0 } },
          turnin = { text = "Turn in Quest 30 to Trainer Test", map = 7001, x = 12.0, y = 13.0 } },
      },
    },
  },
}
