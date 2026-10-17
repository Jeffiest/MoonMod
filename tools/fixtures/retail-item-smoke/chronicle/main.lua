local attempted = false
local item_given_event_count = 0
local item_grant_calls_returned = false
local item_remove_call_returned = false
local item_given_quest_id = "moonfactory.retail-item-probe:retail-item-grants"
local item_removed_quest_id = "moonfactory.retail-item-probe:retail-item-removals"
local event_catalog = assert(game.events.list())
assert(event_catalog.game == "chronicle")
local catalogued_events = {}
for _, event in ipairs(event_catalog.events) do catalogued_events[event.name] = true end
assert(catalogued_events["game.item_removed"] and catalogued_events["game.georama.element_changed"] and
       catalogued_events["ui.action"])
assert(not catalogued_events["game.georama.river_changed"])

game.events.subscribe("game.item_given", function(event)
  assert(item_grant_calls_returned, "item-given events must wait until the grant callback returns")
  assert(event.source_mod == "moonfactory.retail-item-probe" and event.frame >= 0)
  if event.kind == "item" then
    assert(event.id == "moonfactory.retail-item-probe:retail-starlight-tonic" and
           event.native_item_no == nil and event.requested == 2 and event.added == 2)
  elseif event.kind == "weapon" then
    assert((event.id == "moonfactory.retail-item-probe:retail-starlight-blade" or
            event.id == "moonfactory.retail-item-probe:retail-quest-blade") and
           event.native_item_no >= 377 and event.requested == nil and event.added == true and event.slot >= 0)
  else
    error("unexpected retail item-given kind " .. tostring(event.kind))
  end
  item_given_event_count = item_given_event_count + 1
  assert(item_given_event_count <= 3, "only the API item, initial weapon, and quest weapon grants should publish")
  if item_given_event_count == 2 then
    local progress = assert(game.quests.get({id = item_given_quest_id}))
    assert(progress.status == "completed" and progress.objectives[1].progress == 1 and
           progress.objectives[2].progress == 1)
    moonmod.log("info", "MOONFACTORY_RETAIL_ITEM_GIVEN_QUEST_OK|" .. item_given_quest_id .. "|" ..
                item_given_event_count)
  elseif item_given_event_count == 3 then
    local owned = assert(game.weapons.get("moonfactory.retail-item-probe:retail-quest-blade"))
    assert(owned.owned_count == 1, "the completed quest should grant its registered weapon")
    moonmod.log("info", "MOONFACTORY_RETAIL_WEAPON_QUEST_REWARD_OK|" ..
                "moonfactory.retail-item-probe:retail-quest-blade|" .. owned.owned_count)
  end
end)

game.events.subscribe("quests.completed", function(event)
  if event.id ~= item_given_quest_id then return end
  assert(type(event.rewards) == "table" and #event.rewards == 1)
  local reward = event.rewards[1]
  assert(reward.kind == "weapon" and reward.id == "moonfactory.retail-item-probe:retail-quest-blade" and
         reward.status == "granted" and reward.requested == 1 and reward.result.added == true,
         "Chronicle quest completion should report a successful boolean weapon-grant result")
  local owned = assert(game.weapons.get(reward.id))
  assert(owned.owned_count == 1, "the quest should grant its distinct weapon through native inventory")
end)

game.events.subscribe("game.item_removed", function(event)
  assert(item_remove_call_returned, "item-removed events must wait until items.remove returns")
  assert(event.id == "moonfactory.retail-item-probe:retail-starlight-tonic" and
         event.source_mod == "moonfactory.retail-item-probe" and event.frame >= 0)
  assert(event.requested == 1 and event.removed == 1 and event.remaining == 0)
  local progress = assert(game.quests.get({id = item_removed_quest_id}))
  assert(progress.status == "completed" and progress.objectives[1].progress == 1)
  moonmod.log("info", "MOONFACTORY_RETAIL_ITEM_REMOVED_QUEST_OK|" .. item_removed_quest_id .. "|1")
end)

game.events.subscribe("game.scene.entered", function(scene)
  if attempted or scene.scene_id ~= "town" then return end
  attempted = true

  local item = assert(game.items.register({
    id = "retail-starlight-tonic",
    name = "Retail Starlight Tonic",
    kind = "consumable",
    template_item = 148,
    assets = {},
    effect = {kind = "heal", amount = 25}
  }))
  assert(item.id == "moonfactory.retail-item-probe:retail-starlight-tonic")
  assert(item.status == "registered" and item.mod_owned and item.template_item == 148)
  assert(item.native_item_no ~= item.template_item)
  assert(not item.assets or next(item.assets) == nil, "the test item must not provide asset overrides")
  local capacity_item
  for index = 1, 11 do
    capacity_item = assert(game.items.register({
      id = "retail-capacity-" .. index,
      name = "Retail Capacity " .. index,
      kind = "consumable",
      template_item = 148,
      assets = {},
      effect = {kind = "heal", amount = index}
    }))
  end
  local capacity_readback = assert(game.items.get(capacity_item.id))
  assert(capacity_readback.native_item_no == capacity_item.native_item_no)
  local legacy_reserved_slots = {143, 144, 156, 157, 158, 184, 194, 214, 215, 223, 232}
  for _, slot in ipairs(legacy_reserved_slots) do
    assert(capacity_item.native_item_no ~= slot, "the twelfth mod item must use an expanded native row")
  end
  moonmod.log("info", "MOONFACTORY_RETAIL_ITEM_CAPACITY_OK|12|" .. capacity_item.native_item_no)
  local item_given_quest = assert(game.quests.register({
    id = "retail-item-grants",
    title = "Receive the Retail Probe Content",
    objectives = {
      {id = "receive-tonic", title = "Receive the tonic", target = 1,
       event = "game.item_given", match = {id = item.id, kind = "item"}},
      {id = "receive-blade", title = "Receive the blade", target = 1,
       event = "game.item_given", match = {id = "moonfactory.retail-item-probe:retail-starlight-blade", kind = "weapon"}}
    },
    rewards = {{kind = "weapon", id = "moonfactory.retail-item-probe:retail-quest-blade"}}
  }))
  assert(item_given_quest.id == item_given_quest_id)
  assert(assert(game.quests.start({id = item_given_quest_id})).status == "active")
  local item_removed_quest = assert(game.quests.register({
    id = "retail-item-removals",
    title = "Turn In the Retail Probe Tonic",
    objectives = {{id = "turn-in-tonic", title = "Turn in the tonic", target = 1,
                   event = "game.item_removed", match = {id = item.id}}}
  }))
  assert(item_removed_quest.id == item_removed_quest_id)
  assert(assert(game.quests.start({id = item_removed_quest_id})).status == "active")

  local initial = assert(game.player.get())
  local target_hp = math.min(initial.max_hp - 25, 50)
  assert(target_hp >= 6, "the active character needs enough HP for the damage/use check")
  assert(game.player.set({hp = target_hp, character = "active"}))
  assert(game.player.damage({amount = 5, character = "active"}))
  local damaged = assert(game.player.get())
  assert(damaged.hp == target_hp - 5)

  local grant = assert(game.items.give({id = item.id, count = 2}))
  assert(grant.added == 2)
  assert(item_given_event_count == 0, "item-given event must be deferred beyond items.give")
  local use = assert(game.items.use({id = item.id, character = "active"}))
  assert(use.healing == 25 and use.consumed == 1 and use.remaining == 1)
  assert(use.hp_target == damaged.hp + 25,
         "native item use should queue the exact uncapped HP target")
  local removed = assert(game.items.remove({id = item.id, count = 1}))
  assert(removed.requested == 1 and removed.removed == 1 and removed.remaining == 0)
  item_remove_call_returned = true

  local weapon = assert(game.content.register({
    type = "weapon",
    definition = {
      id = "retail-starlight-blade",
      name = "Retail Starlight Blade",
      template_weapon = "chronicle:weapon:258",
      owner = "toan",
      stats = {attack = 37, durability = 81},
      stat_caps = {attack = 99, magic = 40},
      assets = {}
    }
  }))
  assert(weapon.id == "moonfactory.retail-item-probe:retail-starlight-blade")
  assert(weapon.status == "registered" and weapon.mod_owned and weapon.template_weapon == "chronicle:weapon:258")
  assert(weapon.native_item_no >= 377 and weapon.native_item_no < 409)
  assert(not weapon.assets or weapon.assets.overridden == false)
  local quest_weapon = assert(game.weapons.register({
    id = "retail-quest-blade",
    name = "Retail Quest Blade",
    template_weapon = "chronicle:weapon:258",
    owner = "toan",
    stats = {attack = 41, durability = 96},
    stat_caps = {attack = 99, magic = 40},
    assets = {}
  }))
  assert(quest_weapon.id == "moonfactory.retail-item-probe:retail-quest-blade" and
         quest_weapon.status == "registered" and quest_weapon.native_item_no ~= weapon.native_item_no)
  local weapon_grant = assert(game.weapons.give({id = weapon.id}))
  assert(weapon_grant.added and weapon_grant.native_item_no == weapon.native_item_no)
  assert(item_given_event_count == 0, "item-given event must be deferred beyond weapons.give")
  item_grant_calls_returned = true
  local owned_weapon = assert(game.weapons.get(weapon.id))
  assert(owned_weapon.owned_count >= 1 and owned_weapon.instances ~= nil)

  local content = assert(game.content.list())
  local listed_weapon = false
  for _, entry in ipairs(content.entries) do
    if entry.id == weapon.id and entry.content_type == "weapon" then listed_weapon = true end
  end
  assert(listed_weapon and content.count == #content.entries)

  moonmod.log("info", "MOONFACTORY_RETAIL_ITEM_OK|" .. item.id .. "|" .. use.hp_target)
  moonmod.log("info", "MOONFACTORY_RETAIL_CONTENT_OK|" .. content.count)
  moonmod.log("info", "MOONFACTORY_RETAIL_WEAPON_OK|" .. weapon.id .. "|" .. weapon.native_item_no .. "|" .. weapon_grant.slot)
end)

return {}
