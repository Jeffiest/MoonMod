local registered_dungeon
local transition_requested = false
local dungeon_scene_entered = false
local floor_entered = false
local probe_finished = false
local dungeon_ticks = 0
local floor_id = "moonfactory.retail-dungeon-probe:moon-vault:annex"

game.events.subscribe("game.scene.entered", function(scene)
  if scene.scene_id == "town" and not transition_requested then
    registered_dungeon = assert(game.dungeons.register({
      id = "moon-vault",
      name = "Moon Vault",
      dungeon = 0,
      floors = {{id = "annex", name = "Moon Vault Annex", source_floor = 2}}
    }))
    assert(registered_dungeon.id == "moonfactory.retail-dungeon-probe:moon-vault")
    assert(registered_dungeon.floor_count == 16 and registered_dungeon.floors[1].native_floor_id == 15)

    local transition = assert(game.world.transition({id = floor_id}))
    assert(transition.queued and transition.context == "dungeon_floor")
    assert(transition.native_dungeon_id == 0 and transition.native_floor_id == 15)
    transition_requested = true
    moonmod.log("info", "MOONFACTORY_RETAIL_DUNGEON_QUEUED|" .. floor_id .. "|15")
  elseif scene.scene_id == "dungeon" and transition_requested and not floor_entered then
    dungeon_scene_entered = true
    moonmod.log("info", "MOONFACTORY_RETAIL_DUNGEON_SCENE_ENTERED|" .. scene.scene_id)
  end
end)

game.events.subscribe("game.tick", function(tick)
  if not dungeon_scene_entered or floor_entered or probe_finished then return end
  dungeon_ticks = dungeon_ticks + 1
  if not floor_entered then
    local world, world_error = game.world.get()
    if dungeon_ticks % 30 == 0 then
      if world then
        moonmod.log("info", "MOONFACTORY_RETAIL_DUNGEON_WORLD|" .. dungeon_ticks .. "|" .. tostring(world.context) .. "|" ..
                    tostring(world.dungeon_id) .. "|" .. tostring(world.floor_id))
      else
        moonmod.log("warning", "MOONFACTORY_RETAIL_DUNGEON_WORLD_ERROR|" .. dungeon_ticks .. "|" ..
                    tostring(world_error and world_error.message or world_error))
      end
    end
    if world and world.context == "dungeon" and world.dungeon_id == 0 and world.floor_id == 15 then
      floor_entered = true
      moonmod.log("info", "MOONFACTORY_RETAIL_DUNGEON_OK|" .. floor_id .. "|" .. world.floor_id .. "|" .. world.context)
    elseif dungeon_ticks > 180 then
      probe_finished = true
      moonmod.log("warning", "MOONFACTORY_RETAIL_DUNGEON_UNVERIFIED|" .. tostring(world and world.context) .. "|" ..
                  tostring(world and world.dungeon_id) .. "|" .. tostring(world and world.floor_id))
      return
    else
      return
    end
  end
end)

return {}
