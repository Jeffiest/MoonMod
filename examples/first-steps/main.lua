local quest_id = "first-journey"
local cookie_template = moonmod.game.id == "chronicle-two" and 274 or 148
local moon_cookie, moon_cookie_error = game.items.register({
  id = "moon-cookie",
  name = "Moon Cookie",
  kind = "consumable",
  template_item = cookie_template,
  assets = {},
  effect = {kind = "heal", amount = 25}
})
if not moon_cookie then
  error(moon_cookie_error and moon_cookie_error.message or "Moon Cookie registration failed")
end

assert(game.quests.register({
  id = quest_id,
  title = "A Small Journey",
  description = "Mark a clue, then visit a town.",
  rewards = {
    {kind = "currency", amount = 25},
    {kind = "item", id = moon_cookie.id, count = 1}
  },
  objectives = {
    {id = "clue", title = "Mark the first clue", target = 1},
    {id = "town", title = "Enter a town", target = 1,
      event = "game.scene.entered", match = {scene_id = "town"}}
  }
}))

assert(game.skills.register({
  id = "trailblazer",
  title = "Trailblazer",
  description = "A tiny example skill tree.",
  skills = {
    {id = "focus", title = "Focused Strike", description = "The first rank.", max_rank = 2,
      effects = {enemy_damage_per_rank = 0.1}},
    {id = "power", title = "Heavy Blow", description = "Requires one rank of Focused Strike.",
      max_rank = 1, prerequisites = {{id = "focus", rank = 1}}}
  }
}))

assert(game.ui.register({id = "start-journey", label = "Start journey",
  description = "Start the sample quest."}))
assert(game.ui.register({id = "mark-clue", label = "Mark first clue",
  description = "Advance the first quest objective."}))
assert(game.ui.register({id = "unlock-focus", label = "Unlock Focus",
  description = "Add one rank to Focused Strike."}))

local function current_quest()
  return assert(game.quests.get({id = quest_id}))
end

moonmod.on("runtime.loaded", function()
  if moonmod.settings.get("show_log") then
    moonmod.log("info", "First Steps is ready. Open its Actions, Quests, and Skills tabs.")
  end
end)

moonmod.on("quests.completed", function(event)
  if event.id == "example.first-steps:" .. quest_id then
    assert(event.rewards and #event.rewards == 2)
    assert(event.rewards[1].kind == "currency" and event.rewards[1].status == "granted")
    assert(event.rewards[1].result.added == 25)
    assert(event.rewards[2].kind == "item" and event.rewards[2].id == moon_cookie.id)
    assert(event.rewards[2].status == "granted" and event.rewards[2].result.added == 1)
    moonmod.log("info", "FIRST_STEPS_REWARDS_GRANTED")
  end
end)

moonmod.on("ui.action", function(action)
  if action.id == "start-journey" then
    if current_quest().status == "registered" then
      assert(game.quests.start({id = quest_id}))
    end
  elseif action.id == "mark-clue" then
    local quest = current_quest()
    if quest.status == "active" and quest.objectives[1].progress < quest.objectives[1].target then
      assert(game.quests.advance({id = quest_id, objective = "clue"}))
    end
  elseif action.id == "unlock-focus" then
    local skill = assert(game.skills.get({id = "trailblazer.focus"}))
    if skill.rank < skill.max_rank then
      assert(game.skills.unlock({id = "trailblazer.focus"}))
    end
  end
end)
