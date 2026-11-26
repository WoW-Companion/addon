WoWCompanionPlan = {
  schema = "1.0", generated = 1795363809,
  characters = {
    ["Thrall"] = {
      steps = {
        { n = 1, kind = "turnin", questID = 10, quest = "Quest 10", label = "Turn in Quest 10", map = 7001, x = 50.0, y = 50.0 },
        { n = 2, kind = "pickup", questID = 12, quest = "Quest 12", label = "Open the bank", map = 7001, x = 70.0, y = 50.0 },
      },
      trips = { { order = 1, map = 7002, zone = "Otherisle", ready = 1, todo = 0, pickups = 0, questIDs = { 20 } } },
      find = { { questID = 50, quest = "Anyone Can Cook", hint = "Find an ogre who can read the Illegible Recipe", zone = "Undercity" },
               { questID = 51, hint = "bad entry without a name still reads" }, { questID = "x" } },
      errands = { { n = 2, kind = "bank" }, { n = 1, kind = "nonsense" } },
    },
  },
}
