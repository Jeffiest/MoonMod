local attempted = false
local item_completed = false
local transition_queued = false
local dungeon_entered = false
local added_floor = nil
local next_probe_frame = 0
local probe_attempts = 0
local transition_waits = 0
local registered_character = nil
local last_spawn_error = "unknown error"
local defeat_quest_id = nil
local defeat_handle = nil
local defeat_damage_attempts = 0
local defeat_damage_queued = false
local item_given_event_count = 0
local item_grant_calls_returned = false
local item_remove_call_returned = false
local item_given_quest_id = "moonfactory.retail-item-probe:retail-item-grants"
local item_given_weapon_reward_id = "moonfactory.retail-item-probe:retail-quest-blade"
local item_removed_quest_id = "moonfactory.retail-item-probe:retail-item-removals"
local native_pickup_quest_id = "moonfactory.retail-item-probe:native-item-pickup"
local native_pickup_quest_started = false
local function require_result(label, value, err)
  if value == nil then
    local detail = type(err) == "table" and (err.message or err.code) or err
    error(label .. " failed: " .. tostring(detail))
  end
  return value
end

local event_catalog = require_result("events.list", game.events.list())
assert(event_catalog.game == "chronicle-two")
local catalogued_events = {}
for _, event in ipairs(event_catalog.events) do catalogued_events[event.name] = true end
assert(catalogued_events["game.item_removed"] and catalogued_events["game.georama.river_changed"] and
       catalogued_events["ui.action"])
assert(not catalogued_events["game.georama.element_changed"])

game.events.subscribe("quests.completed", function(completed)
  if completed.id == item_given_quest_id then
    assert(type(completed.rewards) == "table" and #completed.rewards == 1)
    local reward = completed.rewards[1]
    assert(reward.kind == "weapon" and reward.id == item_given_weapon_reward_id and
           reward.status == "granted" and reward.requested == 1 and
           (reward.result.added == 1 or reward.result.added == true),
           "Chronicle Two quest completion should report a successful weapon-grant result")
    local owned = require_result("weapons.get after quest reward", game.weapons.get(reward.id))
    assert(owned.owned_count == 1, "the quest should grant its distinct weapon through native inventory")
  end
  if completed.id ~= defeat_quest_id then return end
  assert(defeat_damage_queued, "the enemy-defeat quest must complete after the lethal combat request")
  moonmod.log("info", "MOONFACTORY_RETAIL_ENEMY_DEFEAT_QUEST_OK|" .. defeat_quest_id .. "|" ..
              tostring(defeat_handle))
end)

game.events.subscribe("game.item_removed", function(event)
  assert(item_remove_call_returned, "item-removed events must wait until items.remove returns")
  assert(event.id == "moonfactory.retail-item-probe:retail-starlight-tonic" and
         event.source_mod == "moonfactory.retail-item-probe" and event.frame >= 0)
  assert(event.requested == 1 and event.removed == 1 and event.remaining == 0)
  local progress = require_result("quests.get item-removed progress", game.quests.get({id = item_removed_quest_id}))
  assert(progress.status == "completed" and progress.objectives[1].progress == 1)
  moonmod.log("info", "MOONFACTORY_RETAIL_ITEM_REMOVED_QUEST_OK|" .. item_removed_quest_id .. "|1")
end)

game.events.subscribe("game.item_picked_up", function(event)
  assert(event.id == "chronicle-two:item:274" and event.kind == "item" and
         event.native_item_no == 274 and event.count == 1 and event.source == "native" and event.frame >= 0,
         "native pickup event should identify the built-in item and successful inventory amount")
  local progress = require_result("quests.get native pickup progress", game.quests.get({id = native_pickup_quest_id}))
  assert(progress.status == "completed" and progress.objectives[1].progress == 1,
         "the native pickup should complete its filtered event quest")
  moonmod.log("info", "MOONFACTORY_RETAIL_NATIVE_ITEM_PICKUP_OK|" .. event.id .. "|" .. event.count)
end)

game.events.subscribe("game.scene.will_enter", function(scene)
  if scene.scene_id ~= "dungeon" or native_pickup_quest_started then return end
  local quest = require_result("quests.register native pickup quest", game.quests.register({
    id = "native-item-pickup",
    title = "Collect a Dungeon Find",
    objectives = {{id = "collect-built-in-item", title = "Collect the built-in item", target = 1,
                   event = "game.item_picked_up", match = {id = "chronicle-two:item:274", kind = "item"}}}
  }))
  assert(quest.id == native_pickup_quest_id)
  assert(require_result("quests.start native pickup quest", game.quests.start({id = native_pickup_quest_id})).status == "active")
  native_pickup_quest_started = true
end)

game.events.subscribe("game.enemy_defeated", function(defeated)
  moonmod.log("info", "MOONFACTORY_RETAIL_ENEMY_DEFEAT_EVENT|" .. tostring(defeated.character_id) .. "|" ..
              tostring(defeated.entity) .. "|" .. tostring(defeated.source) .. "|" ..
              tostring(defeated.native_monster_id))
end)

game.events.subscribe("game.item_given", function(event)
  assert(item_grant_calls_returned, "item-given events must wait until the grant callback returns")
  assert(event.source_mod == "moonfactory.retail-item-probe" and event.frame >= 0)
  if event.kind == "item" then
    assert(event.id == "moonfactory.retail-item-probe:retail-starlight-tonic" and
           event.native_item_no == nil and event.requested == 2 and event.added == 2)
  elseif event.kind == "weapon" then
    assert((event.id == "moonfactory.retail-item-probe:retail-starlight-blade" or
            event.id == item_given_weapon_reward_id) and
           event.native_item_no > 0 and event.requested == 1 and event.added == 1 and event.slot == nil)
  else
    error("unexpected retail item-given kind " .. tostring(event.kind))
  end
  item_given_event_count = item_given_event_count + 1
  assert(item_given_event_count <= 3, "only the API item, initial weapon, and quest weapon grants should publish")
  if item_given_event_count == 2 then
    local progress = require_result("quests.get item-given progress", game.quests.get({id = item_given_quest_id}))
    assert(progress.status == "completed" and progress.objectives[1].progress == 1 and
           progress.objectives[2].progress == 1)
    moonmod.log("info", "MOONFACTORY_RETAIL_ITEM_GIVEN_QUEST_OK|" .. item_given_quest_id .. "|" ..
                item_given_event_count)
  elseif item_given_event_count == 3 then
    local owned = require_result("weapons.get after quest reward event", game.weapons.get(item_given_weapon_reward_id))
    assert(owned.owned_count == 1, "the completed quest should grant its distinct native weapon")
    moonmod.log("info", "MOONFACTORY_RETAIL_WEAPON_QUEST_REWARD_OK|" ..
                item_given_weapon_reward_id .. "|" .. owned.owned_count)
  end
end)

local item = assert(game.items.register({
  id = "retail-starlight-tonic",
  name = "Retail Starlight Tonic",
  kind = "consumable",
  template_item = 274,
  assets = {},
  effect = {kind = "heal", amount = 25}
}))
assert(item.id == "moonfactory.retail-item-probe:retail-starlight-tonic")
assert(item.status == "pending" and item.mod_owned and item.template_item == 274)
assert(not item.assets or next(item.assets) == nil, "the test item must not provide asset overrides")

local weapon = assert(game.weapons.register({
  id = "retail-starlight-blade",
  name = "Retail Starlight Blade",
  template_weapon = 80,
  stats = {attack = 18, durability = 125},
  stat_caps = {attack = 120, durability = 500},
  assets = {}
}))
assert(weapon.id == "moonfactory.retail-item-probe:retail-starlight-blade")
assert(weapon.status == "pending" and weapon.template_weapon == 80)
assert(not weapon.assets or next(weapon.assets) == nil,
       "the test weapon must inherit its native model and icon without asset overrides")
local quest_weapon = assert(game.weapons.register({
  id = "retail-quest-blade",
  name = "Retail Quest Blade",
  template_weapon = 80,
  stats = {attack = 19, durability = 140},
  stat_caps = {attack = 120, durability = 500},
  assets = {}
}))
assert(quest_weapon.id == item_given_weapon_reward_id and quest_weapon.status == "pending" and
       quest_weapon.template_weapon == 80)
assert(not quest_weapon.assets or next(quest_weapon.assets) == nil,
       "the quest reward weapon must inherit native model and icon without asset overrides")

local dungeon = assert(game.dungeons.register({
  id = "retail-moon-vault",
  name = "Retail Moon Vault",
  dungeon = 0,
  floors = {
    {id = "annex", name = "Retail Moon Vault Annex", source_floor = 1,
     flags = {"exit", "boss"}, seal = "max"}
  }
}))
assert(dungeon.id == "moonfactory.retail-item-probe:retail-moon-vault")
assert(dungeon.floors[1].status == "pending")

game.events.subscribe("game.scene.entered", function(scene)
  if scene.scene_id ~= "dungeon" then return end
  if attempted then
    if not transition_queued or dungeon_entered then return end
    local current = require_result("world.get after floor transition", game.world.get())
    if current.context == "dungeon" and current.dungeon_id == dungeon.dungeon and
       current.floor_id == added_floor.native_floor_id then
      dungeon_entered = true
    else
      error("native loop re-entry did not enter the registered floor: " ..
            tostring(current.context) .. "|" .. tostring(current.floor_id))
    end
    return
  end
  attempted = true

  local registered = require_result("items.get", game.items.get(item.id))
  assert(registered.status == "registered" and registered.mod_owned and registered.template_item == 274)
  assert(not registered.assets or next(registered.assets) == nil,
         "the registered test item must not provide asset overrides")

  local registered_weapon = require_result("weapons.get after native table load", game.weapons.get(weapon.id))
  assert(registered_weapon.status == "registered" and registered_weapon.mod_owned and
         registered_weapon.native_item_no ~= nil and registered_weapon.native_item_no > 0,
         "the data-only weapon should materialize in the native weapon table")
  assert(registered_weapon.stats.attack == 18 and registered_weapon.stats.durability == 125)
  local item_given_quest = require_result("quests.register item-given quest", game.quests.register({
    id = "retail-item-grants",
    title = "Receive the Retail Probe Content",
    objectives = {
      {id = "receive-tonic", title = "Receive the tonic", target = 1,
       event = "game.item_given", match = {id = item.id, kind = "item"}},
      {id = "receive-blade", title = "Receive the blade", target = 1,
       event = "game.item_given", match = {id = weapon.id, kind = "weapon"}}
    },
    rewards = {{kind = "weapon", id = quest_weapon.id}}
  }))
  assert(item_given_quest.id == item_given_quest_id)
  assert(require_result("quests.start item-given quest", game.quests.start({id = item_given_quest_id})).status == "active")
  local item_removed_quest = require_result("quests.register item-removed quest", game.quests.register({
    id = "retail-item-removals",
    title = "Turn In the Retail Probe Tonic",
    objectives = {{id = "turn-in-tonic", title = "Turn in the tonic", target = 1,
                   event = "game.item_removed", match = {id = item.id}}
    }
  }))
  assert(item_removed_quest.id == item_removed_quest_id)
  assert(require_result("quests.start item-removed quest", game.quests.start({id = item_removed_quest_id})).status == "active")
  local weapon_grant = require_result("weapons.give", game.weapons.give({id = weapon.id}))
  assert(weapon_grant.added == 1 and weapon_grant.native_item_no == registered_weapon.native_item_no,
         "the native inventory route should grant the registered weapon")
  assert(item_given_event_count == 0, "item-given event must be deferred beyond weapons.give")
  local owned_weapon = require_result("weapons.get after grant", game.weapons.get(weapon.id))
  assert(owned_weapon.owned_count == 1,
         "weapons.get should report the granted mod weapon in the active save inventory")
  local weapons = require_result("weapons.list", game.weapons.list())
  local listed_weapon = false
  for _, entry in ipairs(weapons) do
    if entry.id == weapon.id and entry.native_item_no == registered_weapon.native_item_no and entry.mod_owned then
      listed_weapon = true
    end
  end
  assert(listed_weapon, "weapons.list should include the native-backed mod weapon")
  moonmod.log("info", "MOONFACTORY_RETAIL_WEAPON_OK|" .. weapon.id .. "|" ..
    registered_weapon.native_item_no .. "|" .. weapon_grant.added .. "|" .. owned_weapon.owned_count)

  local loaded_dungeon = require_result("dungeons.get", game.dungeons.get(dungeon.id))
  added_floor = loaded_dungeon.floors[1]
  assert(added_floor.status == "registered" and added_floor.native_floor_id ~= nil,
         "the data-only floor must be materialized in the loaded native dungeon map")
  assert(added_floor.name == "Retail Moon Vault Annex" and added_floor.source_floor == 1)
  assert(added_floor.flags[1] == "exit" and added_floor.flags[2] == "boss" and added_floor.seal == "max")

  -- Register before queuing the added floor so the native dungeon loader can preload
  -- the inherited model/script through its normal floor-initialization path.
  local template_monster_id = 0
  local template = require_result("models.resolve", game.models.resolve({monster_id = template_monster_id}))
  registered_character = require_result("characters.register", game.characters.register({
    id = "retail-annex-sentinel",
    kind = "enemy",
    name = "Retail Annex Sentinel",
    template_monster_id = template_monster_id,
    stats = {hp = 300, attack = 75, defense = 41},
    assets = {}
  }))
  assert(registered_character.status == "registered" and registered_character.native_monster_id > 0)
  assert(registered_character.model == template.model and registered_character.script == template.script)

  local defeat_quest = require_result("quests.register enemy defeat objective", game.quests.register({
    id = "annex-sentinel-hunt",
    title = "Annex Sentinel Hunt",
      objectives = {{
        id = "spawn-sentinel",
        title = "Spawn the Sentinel",
        target = 1,
        event = "game.enemy_spawned",
        match = {character_id = registered_character.id}
      }, {
      id = "defeat-sentinel",
      title = "Defeat the Sentinel",
      target = 1,
      event = "game.enemy_defeated",
      match = {character_id = registered_character.id}
    }}
  }))
  defeat_quest_id = defeat_quest.id
  require_result("quests.start enemy defeat objective", game.quests.start({id = defeat_quest_id}))
  game.events.subscribe("game.enemy_spawned", function(spawned)
    assert(spawned.character_id == registered_character.id and spawned.slot >= 0 and spawned.generation > 0)
    assert(type(spawned.position) == "table" and type(spawned.position.x) == "number" and
           type(spawned.position.y) == "number" and type(spawned.position.z) == "number")
    assert(spawned.native_monster_id > 0 and spawned.source_mod == "moonfactory.retail-item-probe" and
           spawned.frame >= 0)
    moonmod.log("info", "MOONFACTORY_RETAIL_ENEMY_SPAWNED_EVENT|" .. tostring(spawned.character_id) .. "|" ..
                tostring(spawned.entity) .. "|" .. tostring(spawned.native_monster_id) .. "|" ..
                tostring(spawned.slot) .. "|" .. tostring(spawned.generation) .. "|" ..
                tostring(spawned.source_mod) .. "|" .. tostring(spawned.frame))
  end)

  local initial = require_result("player.get", game.player.get())
  assert(initial.character == "max", "the dungeon test checkpoint must control Max")
  local target_hp = math.max(2, math.floor(initial.max_hp / 2))
  require_result("player.set", game.player.set({hp = target_hp, character = "max"}))
  require_result("player.damage", game.player.damage({amount = 1, character = "max"}))
  local damaged = require_result("player.get after damage", game.player.get())
  assert(damaged.hp == target_hp - 1,
         "expected Max to lose one HP, got " .. tostring(damaged.hp))

  local grant = require_result("items.give", game.items.give({id = item.id, count = 2}))
  assert(grant.added == 2)
  assert(item_given_event_count == 0, "item-given event must be deferred beyond items.give")
  item_grant_calls_returned = true
  local use = require_result("items.use", game.items.use({id = item.id, target = "max"}))
  local expected_heal = math.min(25, damaged.max_hp - damaged.hp)
  assert(use.effects_applied == 1 and use.healed == expected_heal and use.healed > 0 and
         use.consumed == 1 and use.remaining == 1)
  assert(use.hp_before == damaged.hp and use.hp_after == damaged.hp + expected_heal)
  local removed = require_result("items.remove", game.items.remove({id = item.id, count = 1}))
  assert(removed.requested == 1 and removed.removed == 1 and removed.remaining == 0)
  item_remove_call_returned = true

  moonmod.log("info", "MOONFACTORY_RETAIL_ITEM_OK|" .. item.id .. "|" .. use.hp_after)
  item_completed = true

  local transition, transition_error = game.world.transition({id = added_floor.id})
  if transition == nil then
    local detail = type(transition_error) == "table" and
                   (transition_error.message or transition_error.code) or transition_error
    error("world.transition failed before the dungeon's first simulation frame: " .. tostring(detail))
  end
  assert(transition.queued and transition.native_floor_id == added_floor.native_floor_id,
         "the registered annex should queue a native transition before the first simulation frame")
  transition_queued = true
  moonmod.log("info", "MOONFACTORY_RETAIL_DUNGEON_TRANSITION_QUEUED|" .. added_floor.id .. "|" ..
              transition.native_floor_id)
end)

game.events.subscribe("game.tick", function(tick)
  if defeat_handle and not defeat_damage_queued then
    defeat_damage_attempts = defeat_damage_attempts + 1
    local killed = require_result("combat.damage lethal quest probe", game.combat.damage({
      entity = defeat_handle, amount = 1000000
    }))
    if killed.blocked then
      if defeat_damage_attempts > 120 then error("lethal combat.damage remained blocked for the quest probe") end
      return
    end
    assert(killed.death_queued and killed.hp_after == 0,
           "the defeat quest probe must queue a native enemy death")
    defeat_damage_queued = true
    moonmod.log("info", "MOONFACTORY_RETAIL_ENEMY_DEFEAT_QUEUED|" .. defeat_handle)
    return
  end
  if not attempted or not item_completed or tick.frame < next_probe_frame then return end
  next_probe_frame = tick.frame + 10
  if not dungeon_entered then return end
  probe_attempts = probe_attempts + 1

  local current = require_result("world.get while entering annex", game.world.get())
  if current.context ~= "dungeon" or current.dungeon_id ~= dungeon.dungeon or
     current.floor_id ~= added_floor.native_floor_id then
    return
  end

  local player = require_result("player.get before annex sentinel spawn", game.player.get())
  local spawned, spawn_error = game.characters.spawn({
    character = registered_character.id,
    position = {x = player.position.x, y = player.position.y, z = player.position.z}
  })
  if spawned == nil then
    last_spawn_error = type(spawn_error) == "table" and (spawn_error.message or spawn_error.code) or spawn_error
    if probe_attempts == 1 or probe_attempts % 5 == 0 then
      moonmod.log("info", "MOONFACTORY_RETAIL_DUNGEON_WAIT|" .. tick.frame .. "|" .. tostring(last_spawn_error))
    end
    if tick.frame >= 420 then
      moonmod.log("warning", "MOONFACTORY_RETAIL_DUNGEON_UNVERIFIED|native annex room did not accept an enemy spawn: " ..
                  tostring(last_spawn_error))
      dungeon_entered = false
    end
    return
  end

  local live_enemy = require_result("entities.get on annex", game.entities.get({id = spawned.entity_handle}))
  assert(live_enemy.status == "alive" and live_enemy.definition.monster_id == registered_character.native_monster_id)
  assert(live_enemy.health.maximum == 300)
  current = require_result("world.get after annex spawn", game.world.get())
  assert(current.dungeon_id == dungeon.dungeon and current.floor_id == added_floor.native_floor_id)
  dungeon_entered = false
  local orbit = require_result("render.camera_set", game.render.camera_set({angle = 2.25}))
  assert(orbit.scene == "dungeon" and orbit.angle == 2.25,
         "expected the live dungeon follow camera to accept the requested orbit angle")
  local camera = require_result("render.camera_get after orbit update", game.render.camera_get())
  assert(camera.scene == "dungeon", "the active camera should remain available after an orbit update")
  moonmod.log("info", "MOONFACTORY_RETAIL_CAMERA_OK|" .. orbit.angle)
  defeat_handle = spawned.entity_handle
  moonmod.log("info", "MOONFACTORY_RETAIL_DUNGEON_OK|" .. added_floor.id .. "|" ..
              current.floor_id .. "|" .. current.context .. "|" .. spawned.entity_handle)
end)

return {}
