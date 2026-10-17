assert(game.quests.register({
  id = "light-in-the-ruins",
  title = "A Light in the Ruins",
  description = "MoonFactory quest journal preview.",
  rewards = {{kind = "currency", amount = 120}},
  objectives = {
    {id = "find-relic", title = "Find the first relic", target = 4},
    {id = "open-map", title = "Recover the old map", target = 1},
    {id = "light-beacon", title = "Light the beacon", target = 1},
    {id = "return-home", title = "Return to Norune", target = 1}
  }
}))
moonmod.log("info", "MOONFACTORY_MANAGER_UI_READY|moonfactory.manager-ui.journal")
