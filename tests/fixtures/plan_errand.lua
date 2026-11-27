-- The shape of a schema-1.7 Plan.lua: an errand-only run, with find, errands, parked, later and trips.
WoWCompanionPlan = {
  schema = "1.7", generated = 1795363809,
  characters = {
    ["Thrall"] = {
      steps = { { n = 1, kind = "errand", questID = 0, label = "Train now at your class trainer", map = 7001, x = -1.0, y = -1.0, place = "Otherisle", errand = "train" } },
      exit = { label = "Take the boat to Farisle", map = 7001, x = 90, y = 90, via = "boat" },
      trips = { { order = 1, map = 7002, zone = "Farisle", ready = 1, todo = 0, pickups = 0, questIDs = { 20 }, reason = "Turn-ins are there", travel = { "Take the boat" } } },
      parked = { { questID = 40, quest = "Quest 40", why = "Level 40", kind = "pickup" } },
      later = { 30 },
      find = { { questID = 50, quest = "Anyone Can Cook", hint = "Find an ogre who can read the recipe", zone = "Otherisle" } },
      errands = { { n = 1, kind = "train" } },
    },
  },
}
