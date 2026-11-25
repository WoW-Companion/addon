WoWCompanionPlan = {
  schema = "1.3", generated = 1795363809,
  characters = {
    ["Thrall"] = {
      zone = "Testisle",
      steps = {
        { n = 1, kind = "objective", questID = 10, quest = "Quest 10", label = "Collect Test Gyro (0/1)", map = 7001, x = 10.0, y = 70.0, place = "Test Lake" },
        { n = 2, kind = "objective", questID = 10, quest = "Quest 10", label = "Collect Test Core (0/1)", map = 7001, x = 20.0, y = 20.0, place = "Test Camp" },
        { n = 3, kind = "turnin", questID = 10, quest = "Quest 10", label = "Turn in Quest 10 to Test Windshaper", map = 7001, x = 50.0, y = 50.0, place = "Test Village" },
        { n = 4, kind = "pickup", questID = 20, quest = "Quest 20", label = "Pick up Quest 20", map = 7001, x = 50.0, y = 50.0, place = "Test Village", level = 5 },
        { n = 5, kind = "turnin", questID = 50, quest = "Quest 50", label = "Turn in Quest 50 to Test Windshaper", map = 7001, x = 50.0, y = 50.0, place = "Test Village" },
      },
      guidance = {
        [10] = { questID = 10, quest = "Quest 10", steps = { 1, 2, 3 },
          objectives = {
            { text = "Collect Test Gyro", map = 7001, x = 10.0, y = 70.0, place = "Test Lake" },
            { text = "Collect Test Core", map = 7001, x = 20.0, y = 20.0, place = "Test Camp" } },
          turnin = { text = "Turn in Quest 10 to Test Windshaper", map = 7001, x = 50.0, y = 50.0, place = "Test Village" } },
        [30] = { questID = 30, quest = "Quest 30", steps = {},
          objectives = { { text = "Slay Test Drake", map = 7001, x = 80.0, y = 80.0 } },
          turnin = { text = "Turn in Quest 30", map = 7001, x = 12.0, y = 13.0 } },
      },
      here = {
        { npc = "Test Windshaper", npcID = 3, map = 7001, x = 50.0, y = 50.0, place = "Test Village", steps = { 3, 4, 5 },
          can = { "turn in", "train", "buy and sell" },
          quests = {
            { questID = 10, quest = "Quest 10", role = "turnin", text = "x",
              missing = { { text = "Collect Test Gyro (0/1)", map = 7001, x = 10.0, y = 70.0, place = "Test Lake" },
                          { text = "Collect Test Core (0/1)", map = 7001, x = 20.0, y = 20.0, place = "Test Camp" } } },
            { questID = 20, quest = "Quest 20", role = "pickup", text = "x", missing = {} },
            { questID = 50, quest = "Quest 50", role = "turnin", text = "x", missing = {} },
          },
          nearby = { [32] = { questID = 32, quest = "Quest 32", giver = "Test Cultist", map = 7001, x = 55.0, y = 52.0,
            guidance = { questID = 32, quest = "Quest 32", steps = {},
              objectives = { { text = "Burn Test Hut", map = 7001, x = 60.0, y = 60.0 } },
              turnin = { text = "Turn in Quest 32", map = 7001, x = 55.0, y = 52.0 } } } } },
      },
    },
  },
}
