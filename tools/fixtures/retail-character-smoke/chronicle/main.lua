local dungeon_scene_entered = false
local transition_requested = false
local floor_verified = false
local probe_finished = false
local dungeon_ticks = 0
local probe_attempts = 0
local velocity_attempts = 0
local combat_attempts = 0
local combat_verified = false
local skill_bonus_verified = false
local registered_character
local registered_dungeon
local spawned_handle
local custom_model
local registered_animation
local animation_stop_handle
local animation_stop_frame = 0
local defeat_quest_id
local defeat_spawned_handle
local defeat_damage_attempts = 0
local defeat_damage_queued = false
local floor_id = "moonfactory.retail-character-probe:sentinel-depths:sentinel-floor"
local function require_result(label, value, err)
  if value == nil then
    local detail = type(err) == "table" and (err.message or err.code) or err
    error(label .. " failed: " .. tostring(detail))
  end
  return value
end

local function error_detail(err)
  if type(err) == "table" then return tostring(err.message or err.code or "unknown error") end
  return tostring(err or "unknown error")
end

local damage_formula = require_result("combat.register_formula", game.combat.register_formula({
  id = "retail-double-damage", operation = "multiply", value = 2
}))
assert(damage_formula.id == "moonfactory.retail-character-probe:retail-double-damage")
moonmod.log("info", "MOONFACTORY_RETAIL_COMBAT_FORMULA_REGISTERED|" .. damage_formula.id)

local combat_skill_tree = require_result("skills.register", game.skills.register({
  id = "retail-combat",
  title = "Retail Combat Probe",
  skills = {{id = "power", title = "Power", max_rank = 1,
    effects = {enemy_damage_per_rank = 0.5}}}
}))
assert(combat_skill_tree.id == "moonfactory.retail-character-probe:retail-combat")
local reset_combat_skill = require_result("skills.set_rank", game.skills.set_rank({
  id = "retail-combat.power", rank = 0
}))
assert(reset_combat_skill.rank == 0)

local overlay = require_result("debug.overlay_register", game.debug.overlay_register({
  id = "character-probe", text = "CHARACTER PROBE READY"
}))
assert(overlay.status == "registered" and overlay.id == "moonfactory.retail-character-probe:character-probe")
moonmod.log("info", "MOONFACTORY_RETAIL_DEBUG_OVERLAY_OK|" .. overlay.id .. "|" .. overlay.text)

local hud_layer = require_result("render.layer_register", game.render.layer_register({
  id = "character-probe-hud", text = "MOONMOD HUD ACTIVE"
}))
assert(hud_layer.status == "registered" and hud_layer.id == "moonfactory.retail-character-probe:character-probe-hud")
local updated_hud_layer = require_result("render.layer_register update", game.render.layer_register({
  id = "character-probe-hud", text = "MOONMOD HUD VERIFIED"
}))
assert(updated_hud_layer.text == "MOONMOD HUD VERIFIED")
local temporary_hud_layer = require_result("render.layer_register temporary", game.render.layer_register({
  id = "temporary-hud", text = "TEMP HUD"
}))
local removed_hud_layer = require_result("render.layer_remove", game.render.layer_remove({id = "temporary-hud"}))
assert(temporary_hud_layer.status == "registered" and removed_hud_layer.removed == true)
moonmod.log("info", "MOONFACTORY_RETAIL_RENDER_LAYER_OK|" .. updated_hud_layer.id .. "|" ..
  updated_hud_layer.text .. "|" .. tostring(removed_hud_layer.removed))

require_result("resources.override model", game.resources.override({
  path = "resources/retail-model.chr",
  game_path = "dun/monstor/moon_sentinel.chr"
}))
custom_model = require_result("models.register", game.models.register({
  id = "retail-sentinel-model",
  template_monster_id = 0,
  model = "moon_sentinel"
}))
assert(custom_model.id == "moonfactory.retail-character-probe:retail-sentinel-model")
assert(custom_model.status == "registered" and custom_model.model == "moon_sentinel")
registered_animation = require_result("animations.register", game.animations.register({
  id = "retail-sentinel-idle", model = custom_model.id, motion_index = 0
}))
assert(registered_animation.model == custom_model.id and registered_animation.motion_index == 0)

game.events.subscribe("game.scene.entered", function(scene)
  if scene.scene_id == "town" and not transition_requested then
    local native_model = require_result("models.resolve native model", game.models.resolve({monster_id = 0}))
    local replaced_model = require_result("models.replace", game.models.replace({
      monster_id = 0,
      model = custom_model.model
    }))
    assert(replaced_model.changed and replaced_model.game_path == "dun/monstor/moon_sentinel.chr")
    local replacement_state = require_result("models.resolve replacement", game.models.resolve({monster_id = 0}))
    assert(replacement_state.model == custom_model.model and replacement_state.assets[1].overridden)
    local released_model_asset, released_model_asset_error = game.resources.unoverride({
      game_path = "DUN/MONSTOR/MOON_SENTINEL.CHR"
    })
    assert(released_model_asset == nil and type(released_model_asset_error) == "table" and
           string.find(tostring(released_model_asset_error.message), "resources.unoverride", 1, true),
           "resources.unoverride must preserve a model asset while its native binding depends on it")
    local removed_model = require_result("models.remove", game.models.remove({monster_id = 0}))
    assert(removed_model.removed)
    local restored_model = require_result("models.resolve restored model", game.models.resolve({monster_id = 0}))
    assert(restored_model.model == native_model.model)
    moonmod.log("info", "MOONFACTORY_RETAIL_MODEL_REPLACE_OK|0|dun/monstor/moon_sentinel.chr|restored")

    registered_character = require_result("characters.register", game.characters.register({
      id = "retail-sentinel",
      kind = "enemy",
      name = "Retail Sentinel",
      model = custom_model.id,
      stats = {hp = 300, defense = 41, reward_exp = 5, reward_money = 2},
      assets = {}
    }))
    assert(registered_character.id == "moonfactory.retail-character-probe:retail-sentinel")
    assert(registered_character.status == "registered" and registered_character.native_monster_id >= 0x400)
    assert(registered_character.model == "moon_sentinel" and registered_character.model_id == custom_model.id)

    local defeat_quest = require_result("quests.register enemy defeat objective", game.quests.register({
      id = "sentinel-hunt",
      title = "Sentinel Hunt",
      objectives = {{
        id = "spawn-sentinel",
        title = "Spawn the Sentinel",
        target = 2,
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
      assert(spawned.native_model_id > 0 and spawned.source_mod == "moonfactory.retail-character-probe" and
             spawned.frame >= 0)
      moonmod.log("info", "MOONFACTORY_RETAIL_ENEMY_SPAWNED_EVENT|" .. tostring(spawned.character_id) .. "|" ..
                  tostring(spawned.entity) .. "|" .. tostring(spawned.native_model_id) .. "|" ..
                  tostring(spawned.slot) .. "|" .. tostring(spawned.generation) .. "|" ..
                  tostring(spawned.source_mod) .. "|" .. tostring(spawned.frame))
    end)

    registered_dungeon = require_result("dungeons.register", game.dungeons.register({
      id = "sentinel-depths",
      name = "Sentinel Depths",
      dungeon = 0,
      floors = {{
        id = "sentinel-floor",
        name = "Sentinel Floor",
        source_floor = 2,
        enemies = {registered_character.id}
      }}
    }))
    assert(registered_dungeon.floor_count == 16 and registered_dungeon.floors[1].native_floor_id == 15)
    assert(registered_dungeon.floors[1].enemies[1] == registered_character.id)
    local transition = require_result("world.transition", game.world.transition({id = floor_id}))
    assert(transition.queued and transition.context == "dungeon_floor" and transition.native_floor_id == 15)
    transition_requested = true
    moonmod.log("info", "MOONFACTORY_RETAIL_CHARACTER_FLOOR_QUEUED|" .. floor_id .. "|" .. transition.native_floor_id)
  elseif scene.scene_id == "dungeon" and transition_requested then
    dungeon_scene_entered = true
    moonmod.log("info", "MOONFACTORY_RETAIL_CHARACTER_DUNGEON_ENTERED|" .. scene.scene_id)
  end
end)

game.events.subscribe("quests.completed", function(completed)
  if completed.id ~= defeat_quest_id then return end
  assert(defeat_damage_queued, "the enemy-defeat quest must complete after the lethal combat request")
  probe_finished = true
  moonmod.log("info", "MOONFACTORY_RETAIL_ENEMY_DEFEAT_QUEST_OK|" .. defeat_quest_id .. "|" ..
              tostring(defeat_spawned_handle))
end)

game.events.subscribe("game.tick", function(tick)
  if animation_stop_handle ~= nil and tick.frame >= animation_stop_frame and skill_bonus_verified then
    local stopped = require_result("animations.stop", game.animations.stop({entity = animation_stop_handle}))
    assert(stopped.status == "stopped",
           "animations.stop should stop a motion request on the still-owned actor")
    moonmod.log("info", "MOONFACTORY_RETAIL_ANIMATION_STOP_OK|" .. registered_animation.id .. "|" ..
                animation_stop_handle .. "|" .. tostring(stopped.changed))
    local replayed = require_result("animations.play before despawn", game.animations.play({
      animation = registered_animation.id, entity = animation_stop_handle
    }))
    assert(replayed.status == "playing")
    local despawned = require_result("entities.despawn during animation", game.entities.despawn({
      id = animation_stop_handle
    }))
    assert(despawned.status == "despawned" and despawned.changed and despawned.animation_released,
           "despawning an animated actor should release its tracked native motion")
    local stale_stop, stale_stop_error = game.animations.stop({entity = animation_stop_handle})
    assert(stale_stop == nil and string.find(error_detail(stale_stop_error),
           "no active MoonMod animation", 1, true),
           "despawning an animated actor should clear its playback handle")
    moonmod.log("info", "MOONFACTORY_RETAIL_ANIMATION_DESPAWN_CLEANUP_OK|" .. registered_animation.id .. "|" ..
                animation_stop_handle .. "|" .. tostring(despawned.animation_released))
    animation_stop_handle = nil
    local player = require_result("player.get before defeat-quest spawn", game.player.get())
    local spawned = require_result("characters.spawn for defeat quest", game.characters.spawn({
      character = registered_character.id,
      position = {x = player.position.x, y = player.position.y, z = player.position.z}
    }))
    assert(spawned.entity_handle)
    defeat_spawned_handle = spawned.entity_handle
    moonmod.log("info", "MOONFACTORY_RETAIL_ENEMY_DEFEAT_SPAWNED|" .. defeat_spawned_handle)
    return
  end
  if defeat_spawned_handle and not defeat_damage_queued then
    defeat_damage_attempts = defeat_damage_attempts + 1
    local killed = require_result("combat.damage lethal quest probe", game.combat.damage({
      entity = defeat_spawned_handle, amount = 1000000
    }))
    if killed.blocked then
      if defeat_damage_attempts > 120 then error("lethal combat.damage remained blocked for the quest probe") end
      return
    end
    assert(killed.death_queued and killed.hp_after == 0,
           "the defeat quest probe must queue a native enemy death")
    defeat_damage_queued = true
    moonmod.log("info", "MOONFACTORY_RETAIL_ENEMY_DEFEAT_QUEUED|" .. defeat_spawned_handle)
    return
  end
  if not dungeon_scene_entered or probe_finished or defeat_spawned_handle ~= nil then return end
  dungeon_ticks = dungeon_ticks + 1
  if not floor_verified then
    local world = require_result("world.get", game.world.get())
    if world.context ~= "dungeon" or world.dungeon_id ~= 0 or world.floor_id ~= 15 then return end
    floor_verified = true
    moonmod.log("info", "MOONFACTORY_RETAIL_CHARACTER_FLOOR_OK|" .. floor_id .. "|" ..
                world.context .. "|" .. world.floor_id)
  end
  if spawned_handle then
    velocity_attempts = velocity_attempts + 1
    if not combat_verified then
      combat_attempts = combat_attempts + 1
      local damage = require_result("combat.damage", game.combat.damage({entity = spawned_handle, amount = 1}))
      if damage.blocked then
        if combat_attempts > 120 then error("combat.damage remained blocked for the spawned enemy") end
        return
      end
      assert(damage.changed and damage.damage == 2 and damage.hp_after == damage.hp_before - 2,
             "combat.register_formula must double damage to the live spawned enemy")
      local healed = require_result("combat.heal", game.combat.heal({entity = spawned_handle, amount = 2}))
      assert(healed.changed and healed.restored == 2 and healed.hp_after == damage.hp_before,
             "combat.heal must restore the two HP removed by combat.damage")
      local restored_enemy = require_result("entities.get after combat round trip", game.entities.get({id = spawned_handle}))
      assert(restored_enemy.health.current == damage.hp_before,
             "the native enemy health snapshot must reflect the restored HP")
      combat_verified = true
      moonmod.log("info", "MOONFACTORY_RETAIL_COMBAT_FORMULA_OK|" .. damage_formula.id .. "|" .. damage.damage)
      moonmod.log("info", "MOONFACTORY_RETAIL_COMBAT_ROUNDTRIP_OK|" .. registered_character.id .. "|" ..
                  spawned_handle .. "|" .. damage.hp_before .. "|" .. healed.hp_after .. "|" .. healed.restored)
    elseif not skill_bonus_verified then
      local unlocked = require_result("skills.unlock", game.skills.unlock({id = "retail-combat.power"}))
      assert(unlocked.rank == 1)
      local boosted = require_result("combat.damage with skill bonus",
                                     game.combat.damage({entity = spawned_handle, amount = 1}))
      assert(boosted.changed and boosted.damage == 3 and boosted.hp_after == boosted.hp_before - 3,
             "a rank-one 50% skill bonus must stack with the 2x combat formula")
      local restored = require_result("combat.heal after skill bonus",
                                      game.combat.heal({entity = spawned_handle, amount = 3}))
      assert(restored.changed and restored.restored == 3 and restored.hp_after == boosted.hp_before)
      local reset = require_result("skills.set_rank reset", game.skills.set_rank({
        id = "retail-combat.power", rank = 0
      }))
      assert(reset.rank == 0)
      local unboosted = require_result("combat.damage after skill reset",
                                       game.combat.damage({entity = spawned_handle, amount = 1}))
      assert(unboosted.changed and unboosted.damage == 2 and unboosted.hp_after == unboosted.hp_before - 2,
             "resetting the skill rank must remove its native damage bonus")
      local final_heal = require_result("combat.heal after skill reset",
                                        game.combat.heal({entity = spawned_handle, amount = 2}))
      assert(final_heal.changed and final_heal.restored == 2 and final_heal.hp_after == unboosted.hp_before)
      skill_bonus_verified = true
      moonmod.log("info", "MOONFACTORY_RETAIL_SKILL_DAMAGE_BONUS_OK|moonfactory.retail-character-probe:retail-combat.power|" ..
                  boosted.damage .. "|" .. unboosted.damage)
    end
  else
    probe_attempts = probe_attempts + 1
    if probe_attempts > 120 then
      probe_finished = true
      moonmod.log("warning", "MOONFACTORY_RETAIL_CHARACTER_UNVERIFIED|registered floor did not load its custom encounter")
      return
    end
    local model_state = require_result("models.resolve", game.models.resolve({
      monster_id = registered_character.native_monster_id
    }))
    if not model_state.loaded_on_current_floor then return end
  end

  if not spawned_handle then
    local player = require_result("player.get", game.player.get())
    assert(player.position, "player.get must include the active dungeon position")
    local spawned, spawn_error = game.characters.spawn({
      character = registered_character.id,
      position = {x = player.position.x, y = player.position.y, z = player.position.z}
    })
    if spawned == nil then
      if probe_attempts == 1 or probe_attempts % 4 == 0 then
        moonmod.log("info", "MOONFACTORY_RETAIL_CHARACTER_WAIT|" .. tick.frame .. "|" .. error_detail(spawn_error))
      end
      if probe_attempts >= 18 then
        probe_finished = true
        moonmod.log("warning", "MOONFACTORY_RETAIL_CHARACTER_UNVERIFIED|native template " ..
                    registered_character.template_monster_id .. " was not spawnable: " ..
                    error_detail(spawn_error))
      end
      return
    end
    assert(spawned.status == "alive" and spawned.entity_handle)
    spawned_handle = spawned.entity_handle
    local live_enemy = require_result("entities.get", game.entities.get({id = spawned_handle}))
    assert(live_enemy.status == "alive" and live_enemy.character == registered_character.id)
    assert(live_enemy.health.maximum == 300)
    local spatial_query = require_result("physics.query", game.physics.query({
      shape = "sphere",
      center = live_enemy.position,
      radius = 0.1
    }))
    local query_found_spawn = false
    for _, match in ipairs(spatial_query.matches) do
      if match.entity == spawned_handle and match.distance <= 0.1 then query_found_spawn = true end
    end
    assert(query_found_spawn, "physics.query must find the spawned enemy at its live native position")
    moonmod.log("info", "MOONFACTORY_RETAIL_PHYSICS_QUERY_OK|" .. registered_character.id .. "|" ..
                spatial_query.count)
    local resolved_model = require_result("models.resolve", game.models.resolve({
      monster_id = registered_character.native_monster_id
    }))
    assert(resolved_model.model == "moon_sentinel" and resolved_model.loaded_on_current_floor,
           "the registered custom model must be loaded on the current floor")
    moonmod.log("info", "MOONFACTORY_RETAIL_MODEL_OK|" .. custom_model.id .. "|" ..
                resolved_model.assets[1].game_path .. "|loaded")
    moonmod.log("info", "MOONFACTORY_RETAIL_CHARACTER_OK|" .. registered_character.id .. "|" ..
                registered_character.template_monster_id .. "|" .. spawned_handle)
    return
  end

  local motion_before, motion_error = game.physics.velocity_get({entity = spawned_handle})
  if motion_before == nil then
    local detail = error_detail(motion_error)
    if detail:find("native state 1", 1, true) and velocity_attempts < 120 then
      if velocity_attempts == 1 or velocity_attempts % 30 == 0 then
        moonmod.log("info", "MOONFACTORY_RETAIL_VELOCITY_WAIT|" .. tick.frame .. "|" .. detail)
      end
      return
    end
    probe_finished = true
    error("physics.velocity_get failed: " .. detail)
  end
  local target_x = motion_before.velocity.x >= 99999 and motion_before.velocity.x - 1 or
                   motion_before.velocity.x <= -99999 and motion_before.velocity.x + 1 or
                   motion_before.velocity.x + 1
  local motion_set = require_result("physics.velocity_set", game.physics.velocity_set({
    entity = spawned_handle,
    velocity = {x = target_x, y = motion_before.velocity.y, z = motion_before.velocity.z}
  }))
  assert(motion_set.changed and motion_set.previous_velocity.x == motion_before.velocity.x)
  local motion_after = require_result("physics.velocity_get after set", game.physics.velocity_get({entity = spawned_handle}))
  assert(motion_after.velocity.x == target_x and motion_after.velocity.y == motion_before.velocity.y and
         motion_after.velocity.z == motion_before.velocity.z)
  moonmod.log("info", "MOONFACTORY_RETAIL_VELOCITY_SET_OK|" .. registered_character.id .. "|" ..
              motion_after.velocity.x .. "|" .. motion_after.velocity.y .. "|" .. motion_after.velocity.z)
  local playing = require_result("animations.play", game.animations.play({
    animation = registered_animation.id, entity = spawned_handle
  }))
  assert(playing.status == "playing" and playing.motion_index == 0)
  animation_stop_handle = spawned_handle
  animation_stop_frame = tick.frame + 1
  moonmod.log("info", "MOONFACTORY_RETAIL_ANIMATION_PLAY_OK|" .. registered_animation.id .. "|" ..
              spawned_handle .. "|" .. tostring(playing.motion_index))
end)

return {}
