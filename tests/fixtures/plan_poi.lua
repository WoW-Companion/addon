WoWCompanionPlan = {
  schema = "1.2", generated = 1795363809,
  characters = {
    ["Thrall"] = {
      zone = "Testisle",
      steps = {
        { n = 1, kind = "objective", questID = 98095, quest = "Valuable Vantages", label = "Find the vial", map = 7001, x = -1, y = -1, unplaced = true },
        { n = 2, kind = "objective", questID = 10, quest = "Quest 10", label = "Kill Test Wolf", map = 7001, x = 60.0, y = 50.0 },
      },
      guidance = {
        [98095] = { questID = 98095, quest = "Valuable Vantages", steps = { 1 },
          objectives = { { text = "Find the vial" } } },
        [10] = { questID = 10, quest = "Quest 10", steps = { 2 },
          objectives = { { text = "Kill Test Wolf", map = 7001, x = 60.0, y = 50.0 } } },
      },
    },
  },
}
