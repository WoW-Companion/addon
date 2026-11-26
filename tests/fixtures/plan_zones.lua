WoWCompanionPlan = {
  schema = "1.0", generated = 1795363810,
  characters = {
    ["Thrall"] = {
      steps = {
        { n = 1, kind = "objective", questID = 21, quest = "Quest 21", label = "Kill 5 boars", map = 7002, x = 20.0, y = 20.0 },
        { n = 2, kind = "objective", questID = 22, quest = "Quest 22", label = "Kill 5 wolves", map = 7002, x = 70.0, y = 30.0 },
        { n = 3, kind = "pickup", questID = 23, quest = "Quest 23", label = "Pick up Quest 23", map = 7002, x = 40.0, y = 70.0 },
        { n = 4, kind = "turnin", questID = 21, quest = "Quest 21", label = "Turn in Quest 21", map = 7002, x = 80.0, y = 80.0 },
        { n = 5, kind = "objective", questID = 24, quest = "Quest 24", label = "Collect 5 ore", map = 7002, x = 55.0, y = 45.0 },
        { n = 6, kind = "objective", questID = 25, quest = "Quest 25", label = "Loose stop", map = 7002, x = 10.0, y = 90.0 },
      },
      zones = {
        [7002] = {
          arrival = { kind = "flight", npc = "Tharm", name = "Sun Rock Retreat", map = 7002, x = 30.0, y = 55.0,
            text = "Fly to Sun Rock Retreat (Tharm)" },
          order = { 3, 1, 5, 2, 4, 3, 99 },
        },
      },
    },
  },
}
