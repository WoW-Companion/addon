-- A plan with logistics errands: one attached to a step, one standalone repair, one of an unknown kind.
WoWCompanionPlan = {
  schema = "1.7", generated = 1795363809,
  characters = {
    ["Thrall"] = {
      steps = {
        { n = 1, kind = "pickup", questID = 1, quest = "Quest 1", label = "Pick up Quest 1", map = 7001, x = 50.0, y = 10.0 },
        { n = 2, kind = "turnin", questID = 2, quest = "Quest 2", label = "Turn in Quest 2 to Sly", map = 7001, x = 50.0, y = 90.0 },
      },
      errands = {
        { kind = "restock", label = "buy 5 Empty Vial", npc = "Sly Garrett", map = 7001, x = 50.0, y = 90.0, attach = 2 },
        { kind = "repair", label = "Repair your gear", map = 7001, x = 20.0, y = 20.0, why = "durability 12%" },
        { kind = "hologram", label = "Sort the holo-vault", map = 7001, x = 80.0, y = 80.0, attach = 1 },
      },
    },
  },
}
