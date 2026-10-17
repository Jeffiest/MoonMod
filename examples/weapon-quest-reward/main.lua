local quest_id = "weapon-trial"
local weapon_by_game = {
  chronicle = "chronicle:weapon:258",
  ["chronicle-two"] = "chronicle-two:weapon:80"
}
local weapon_id = assert(weapon_by_game[moonmod.game.id], "unsupported game target")

assert(game.quests.register({
  id = quest_id,
  title = "Weapon Trial",
  description = "Start the trial, then complete its objective to receive a weapon.",
  objectives = {{id = "trial", title = "Complete the weapon trial", target = 1}},
  rewards = {{kind = "weapon", id = weapon_id}}
}))

assert(game.ui.register({
  id = "start-trial",
  label = "Start weapon trial",
  description = "Start the sample quest."
}))
assert(game.ui.register({
  id = "complete-trial",
  label = "Complete weapon trial",
  description = "Advance the sample quest and receive its weapon reward."
}))

moonmod.on("quests.completed", function(event)
  if event.id ~= "example.weapon-quest-reward:" .. quest_id then return end
  local reward = event.rewards and event.rewards[1]
  if reward and reward.status == "granted" then
    moonmod.log("info", "WEAPON_QUEST_REWARD_GRANTED|" .. reward.id)
  else
    moonmod.log("warning", "WEAPON_QUEST_REWARD_NOT_GRANTED")
  end
end)

moonmod.on("ui.action", function(action)
  if action.id == "start-trial" then
    local quest = assert(game.quests.get({id = quest_id}))
    if quest.status == "registered" then
      assert(game.quests.start({id = quest_id}))
    end
  elseif action.id == "complete-trial" then
    local quest = assert(game.quests.get({id = quest_id}))
    if quest.status == "active" and quest.objectives[1].progress < quest.objectives[1].target then
      assert(game.quests.advance({id = quest_id, objective = "trial"}))
    end
  end
end)
