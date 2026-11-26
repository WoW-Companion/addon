WoWCompanionPlan = {
  schema = "1.0", generated = 1795363809,
  characters = {
    ["Thrall"] = {
      steps = {
        { n = 1, kind = "objective", questID = 10, quest = "Quest 10", label = "Kill 15 Peasants", map = 7001, x = 60.0, y = 50.0 },
        { n = 2, kind = "objective", questID = 11, quest = "Quest 11", label = "Collect Sword", map = 7001, x = 65.0, y = 50.0 },
        { n = 3, kind = "turnin", questID = 10, quest = "Quest 10", label = "Turn in Quest 10 to Darthalia", map = 7001, x = 50.0, y = 50.0 },
        { n = 4, kind = "turnin", questID = 11, quest = "Quest 11", label = "Turn in Quest 11 to Humbert", map = 7001, x = 50.0, y = 50.0 },
      },
      trips = { { order = 1, map = 7002, zone = "Otherisle", ready = 0, todo = 1, pickups = 0, questIDs = { 30 }, reason = "Far", travel = { "Take the boat" } } },
      parked = { { questID = 40, quest = "Quest 40", why = "Level 40", kind = "pickup" } },
    },
  },
}
