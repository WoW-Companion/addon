WoWCompanionPlan = {
  schema = "1.0", generated = 1795363809,
  characters = {
    ["Thrall"] = {
      steps = {
        { n = 1, kind = "pickup", questID = 10, quest = "Quest 10", label = "Pick up Quest 10", map = 7001, x = 50.0, y = 50.0 },
        { n = 2, kind = "objective", questID = 10, quest = "Quest 10", label = "Kill 5 boars", map = 7001, x = 60.0, y = 50.0 },
        { n = 3, kind = "pickup", questID = 12, quest = "Quest 12", label = "Pick up Quest 12", map = 7001, x = 70.0, y = 50.0 },
        { n = 4, kind = "turnin", questID = 10, quest = "Quest 10", label = "Turn in Quest 10", map = 7001, x = 50.0, y = 50.0 },
        { n = 5, kind = "travel", questID = 0, quest = "", label = "Travel to Otherisle", map = 7002, x = 10.0, y = 10.0 },
        { n = 6, kind = "turnin", questID = 20, quest = "Quest 20", label = "Turn in Quest 20", map = 7002, x = 20.0, y = 20.0 },
      },
      exit = { label = "Take the boat to Otherisle", map = 7001, x = 90, y = 90, via = "boat" },
      trips = {
        { order = 2, map = 7003, zone = "Farisle", ready = 0, todo = 1, pickups = 0, questIDs = { 30 }, reason = "Needs level 20", travel = { "Fly to Farisle" } },
        { order = 1, map = 7002, zone = "Otherisle", ready = 1, todo = 1, pickups = 0, questIDs = { 20, 21, 10 }, reason = "Turn-ins are there", travel = { "Take the boat", "Walk north" } },
      },
      parked = { { questID = 40, quest = "Quest 40", why = "Level 40", kind = "pickup" }, { questID = 30, quest = "Quest 30", why = "dup of a trip" } },
    },
  },
}
