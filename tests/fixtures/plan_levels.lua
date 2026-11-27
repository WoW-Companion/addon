-- A plan whose steps carry the app's level and diff (quest level minus yours): a +6, a +2 and a +12 quest.
WoWCompanionPlan = {
  schema = "1.7", generated = 1795363809,
  characters = {
    ["Thrall"] = {
      steps = {
        { n = 1, kind = "pickup", questID = 10, quest = "Shadowmaw Panther", label = "Pick up Shadowmaw Panther", map = 7001, x = 50.0, y = 50.0, level = 38, diff = 6 },
        { n = 2, kind = "turnin", questID = 10, quest = "Shadowmaw Panther", label = "Turn in Shadowmaw Panther", map = 7001, x = 55.0, y = 50.0, level = 38, diff = 6 },
        { n = 3, kind = "pickup", questID = 12, quest = "Quest 12", label = "Pick up Quest 12", map = 7001, x = 70.0, y = 50.0, level = 34, diff = 2 },
        { n = 4, kind = "pickup", questID = 14, quest = "Quest 14", label = "Pick up Quest 14", map = 7001, x = 80.0, y = 50.0, level = 44, diff = 12 },
      },
      parked = { { questID = 40, quest = "Quest 40", why = "Level 40", kind = "pickup" } },
    },
  },
}
