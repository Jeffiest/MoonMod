local probe_attempted = false
local next_probe_frame = 0
local probe_attempts = 0
local animation_stop_handle = nil
local animation_stop_frame = 0
local combat_probe_handle = nil
local combat_probe_attempts = 0
local combat_probe_verified = false
local skill_bonus_verified = false

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

-- Register during package startup so the native dungeon loader can preload this
-- custom model when it builds the floor's monster reference table.
local template_monster_id = 0
local template = require_result("models.resolve template", game.models.resolve({monster_id = template_monster_id}))
local model_asset = require_result("resources.override model", game.resources.override({
  path = "resources/retail-model.chr",
  game_path = "dungeon/monster/moon_sentinel.chr"
}))
local registered_model = require_result("models.register", game.models.register({
  id = "retail-sentinel-model",
  template_monster_id = template_monster_id,
  model = "moon_sentinel"
}))
assert(model_asset.status == "registered" and registered_model.model == "moon_sentinel")
local registered_animation = require_result("animations.register", game.animations.register({
  id = "retail-sentinel-idle", model = registered_model.id, motion_index = 0
}))
assert(registered_animation.id == "moonfactory.retail-character-probe:retail-sentinel-idle" and
       registered_animation.model == registered_model.id and registered_animation.motion_index == 0)

local replacement_target
for monster_id = 0, 343 do
  local candidate = game.models.resolve({monster_id = monster_id})
  if candidate ~= nil and not candidate.loaded_on_current_floor then
    replacement_target = candidate
    break
  end
end
assert(replacement_target ~= nil, "no unloaded native model was available for replacement verification")
local replaced_native_model = require_result("models.replace", game.models.replace({
  monster_id = replacement_target.monster_id,
  model = registered_model.model
}))
assert(replaced_native_model.changed and replaced_native_model.model == registered_model.model and
       replaced_native_model.game_path == "dungeon/monster/moon_sentinel.chr")
local replacement_state = require_result("models.resolve replacement",
                                          game.models.resolve({monster_id = replacement_target.monster_id}))
assert(replacement_state.model == registered_model.model and replacement_state.assets[1].overridden)
local released_model_asset, released_model_asset_error = game.resources.unoverride({
  game_path = "DUNGEON/MONSTER/MOON_SENTINEL.CHR"
})
assert(released_model_asset == nil and type(released_model_asset_error) == "table" and
       string.find(tostring(released_model_asset_error.message), "resources.unoverride", 1, true),
       "resources.unoverride must preserve a model asset while its native binding depends on it")
local removed_native_model = require_result("models.remove", game.models.remove({
  monster_id = replacement_target.monster_id
}))
assert(removed_native_model.removed and removed_native_model.model == replacement_target.model)
local restored_native_model = require_result("models.resolve restored model",
                                              game.models.resolve({monster_id = replacement_target.monster_id}))
assert(restored_native_model.model == replacement_target.model)
moonmod.log("info", "MOONFACTORY_RETAIL_MODEL_REPLACE_OK|" .. replacement_target.monster_id ..
            "|dungeon/monster/moon_sentinel.chr|restored")

local registered_character = require_result("characters.register", game.characters.register({
  id = "retail-sentinel",
  kind = "enemy",
  name = "Retail Sentinel",
  model = registered_model.id,
  stats = {hp = 300, attack = 75, defense = 41}
}))
assert(registered_character.id == "moonfactory.retail-character-probe:retail-sentinel")
assert(registered_character.status == "registered" and registered_character.native_monster_id > 0)
assert(registered_character.template_monster_id == template_monster_id and
       registered_character.model == "moon_sentinel" and registered_character.script == template.script and
       registered_character.model_id == registered_model.id)

game.events.subscribe("game.scene.entered", function(scene)
  if scene.scene_id == "dungeon" then
    moonmod.log("info", "MOONFACTORY_RETAIL_CHARACTER_DUNGEON_ENTERED|" .. tostring(scene.scene_id))
  end
end)

game.events.subscribe("game.tick", function(tick)
  if combat_probe_handle ~= nil then
    if not combat_probe_verified then
      combat_probe_attempts = combat_probe_attempts + 1
      local damage = require_result("combat.damage", game.combat.damage({entity = combat_probe_handle, amount = 1}))
      if damage.blocked then
        if combat_probe_attempts > 120 then error("combat.damage remained blocked for the spawned enemy") end
        return
      end
      assert(damage.changed and damage.damage == 2 and damage.hp_after == damage.hp_before - 2,
             "combat.register_formula must double damage to the live spawned enemy")
      local healed = require_result("combat.heal", game.combat.heal({entity = combat_probe_handle, amount = 2}))
      assert(healed.changed and healed.restored == 2 and healed.hp_after == damage.hp_before,
             "combat.heal must restore the two HP removed by combat.damage")
      local restored_enemy = require_result("entities.get after combat round trip",
                                            game.entities.get({id = combat_probe_handle}))
      assert(restored_enemy.health.current == damage.hp_before,
             "the native enemy health snapshot must reflect the restored HP")
      combat_probe_verified = true
      moonmod.log("info", "MOONFACTORY_RETAIL_COMBAT_FORMULA_OK|" .. damage_formula.id .. "|" .. damage.damage)
      moonmod.log("info", "MOONFACTORY_RETAIL_COMBAT_ROUNDTRIP_OK|" .. registered_character.id .. "|" ..
                  combat_probe_handle .. "|" .. damage.hp_before .. "|" .. healed.hp_after .. "|" .. healed.restored)
    elseif not skill_bonus_verified then
      local unlocked = require_result("skills.unlock", game.skills.unlock({id = "retail-combat.power"}))
      assert(unlocked.rank == 1)
      local boosted = require_result("combat.damage with skill bonus",
                                     game.combat.damage({entity = combat_probe_handle, amount = 1}))
      assert(boosted.changed and boosted.damage == 3 and boosted.hp_after == boosted.hp_before - 3,
             "a rank-one 50% skill bonus must stack with the 2x combat formula")
      local restored = require_result("combat.heal after skill bonus",
                                      game.combat.heal({entity = combat_probe_handle, amount = 3}))
      assert(restored.changed and restored.restored == 3 and restored.hp_after == boosted.hp_before)
      local reset = require_result("skills.set_rank reset", game.skills.set_rank({
        id = "retail-combat.power", rank = 0
      }))
      assert(reset.rank == 0)
      local unboosted = require_result("combat.damage after skill reset",
                                       game.combat.damage({entity = combat_probe_handle, amount = 1}))
      assert(unboosted.changed and unboosted.damage == 2 and unboosted.hp_after == unboosted.hp_before - 2,
             "resetting the skill rank must remove its native damage bonus")
      local final_heal = require_result("combat.heal after skill reset",
                                        game.combat.heal({entity = combat_probe_handle, amount = 2}))
      assert(final_heal.changed and final_heal.restored == 2 and final_heal.hp_after == unboosted.hp_before)
      skill_bonus_verified = true
      moonmod.log("info", "MOONFACTORY_RETAIL_SKILL_DAMAGE_BONUS_OK|moonfactory.retail-character-probe:retail-combat.power|" ..
                  boosted.damage .. "|" .. unboosted.damage)
    end
  end
  if animation_stop_handle ~= nil and tick.frame >= animation_stop_frame and skill_bonus_verified then
    local stopped = require_result("animations.stop", game.animations.stop({entity = animation_stop_handle}))
    assert(stopped.status == "stopped" and stopped.changed,
           "animations.stop should change the current native motion while the spawned entity is alive")
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
  end
  if probe_attempted or tick.frame < next_probe_frame then return end
  next_probe_frame = tick.frame + 30
  probe_attempts = probe_attempts + 1

  -- Monster 0 is present in Underground Channel's native floor-one spawn table.
  moonmod.log("info", "MOONFACTORY_RETAIL_CHARACTER_TEMPLATE|" .. tick.frame .. "|" .. template_monster_id)

  moonmod.log("info", "MOONFACTORY_RETAIL_CHARACTER_SPAWN_CALL|" .. tick.frame .. "|" .. registered_character.id)
  local spawned, spawn_error = game.characters.spawn({
    character = registered_character.id,
    position = {x = 12, y = 0, z = -8}
  })
  if spawned == nil then
    if probe_attempts == 1 or probe_attempts % 10 == 0 then
      moonmod.log("info", "MOONFACTORY_RETAIL_CHARACTER_WAIT|" .. tick.frame .. "|" .. error_detail(spawn_error))
    end
    if tick.frame >= 150 then
      probe_attempted = true
      moonmod.log("warning", "MOONFACTORY_RETAIL_CHARACTER_UNVERIFIED|native template 0 was not spawnable: " ..
                  error_detail(spawn_error))
    end
    return
  end

  probe_attempted = true
  assert(spawned.status == "alive" and spawned.id == registered_character.id and spawned.entity_handle)
  combat_probe_handle = spawned.entity_handle
  local live_enemy = require_result("entities.get", game.entities.get({id = spawned.entity_handle}))
  assert(live_enemy.status == "alive" and
         live_enemy.definition.monster_id == registered_character.native_monster_id)
  assert(live_enemy.health.maximum == 300)
  local animation_played = require_result("animations.play", game.animations.play({
    animation = registered_animation.id, entity = spawned.entity_handle
  }))
  assert(animation_played.status == "playing" and animation_played.motion_index == 0)
  animation_stop_handle = spawned.entity_handle
  animation_stop_frame = tick.frame + 1
  moonmod.log("info", "MOONFACTORY_RETAIL_ANIMATION_PLAY_OK|" .. registered_animation.id .. "|" ..
              spawned.entity_handle .. "|" .. tostring(animation_played.motion_index))
  local spatial_query = require_result("physics.query", game.physics.query({
    shape = "sphere",
    center = live_enemy.position,
    radius = 0.1
  }))
  local query_found_spawn = false
  for _, match in ipairs(spatial_query.matches) do
    if match.entity == spawned.entity_handle and match.distance <= 0.1 then query_found_spawn = true end
  end
  assert(query_found_spawn, "physics.query must find the spawned enemy at its live native position")
  local resolved_model = require_result("models.resolve spawned custom model",
                                        game.models.resolve({monster_id = registered_character.native_monster_id}))
  assert(resolved_model.model == "moon_sentinel" and resolved_model.model_id == registered_model.id and
         resolved_model.loaded_on_current_floor)
  moonmod.log("info", "MOONFACTORY_RETAIL_MODEL_OK|" .. registered_model.id .. "|" ..
              resolved_model.assets[1].game_path .. "|loaded")
  moonmod.log("info", "MOONFACTORY_RETAIL_PHYSICS_QUERY_OK|" .. registered_character.id .. "|" ..
              spatial_query.count)
  moonmod.log("info", "MOONFACTORY_RETAIL_CHARACTER_OK|" .. registered_character.id .. "|" ..
              template_monster_id .. "|" .. spawned.entity_handle)

  local motion_before = require_result("physics.velocity_get",
                                       game.physics.velocity_get({entity = spawned.entity_handle}))
  local target_x = motion_before.velocity.x >= 99999 and motion_before.velocity.x - 1 or
                   motion_before.velocity.x <= -99999 and motion_before.velocity.x + 1 or
                   motion_before.velocity.x + 1
  local motion_set = require_result("physics.velocity_set", game.physics.velocity_set({
    entity = spawned.entity_handle,
    velocity = {x = target_x, y = motion_before.velocity.y, z = motion_before.velocity.z}
  }))
  assert(motion_set.changed and motion_set.previous_velocity.x == motion_before.velocity.x)
  local motion_after = require_result("physics.velocity_get after set",
                                      game.physics.velocity_get({entity = spawned.entity_handle}))
  assert(motion_after.velocity.x == target_x and motion_after.velocity.y == motion_before.velocity.y and
         motion_after.velocity.z == motion_before.velocity.z)
  moonmod.log("info", "MOONFACTORY_RETAIL_VELOCITY_SET_OK|" .. registered_character.id .. "|" .. motion_after.velocity.x)
end)

return {}
