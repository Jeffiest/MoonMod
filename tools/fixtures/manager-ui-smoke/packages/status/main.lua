local quest_id = "cartographer-note"
assert(game.quests.register({
  id = quest_id,
  title = "The Cartographer Note",
  description = "A visual preview of the consolidated MoonFactory journal.",
  rewards = {{kind = "currency", amount = 120}},
  objectives = {{id = "visit-old-road", title = "Visit the old road", target = 4}}
}))
assert(game.quests.start({id = quest_id}))
assert(game.quests.advance({id = quest_id, objective = "visit-old-road", amount = 2}))
moonmod.log("info", "MOONFACTORY_MANAGER_UI_READY|moonfactory.manager-ui.status")
