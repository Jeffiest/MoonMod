for _, extension in ipairs({"map", "cfg", "stb", "sky"}) do
  local resource = extension == "sky" and "resources/def.sky" or "resources/i01h01." .. extension
  assert(game.resources.override({
    path = resource,
    game_path = "map/m/moo/npr/moonprobe." .. extension
  }))
end

local location = assert(game.locations.register({
  id = "copied-interior",
  map_name = "moonprobe",
  name = "Retail Copied Interior",
  texture_source_map = "i01h01"
}))
moonmod.log("info", "MOONFACTORY_RETAIL_LOCATION_REGISTERED|" .. location.id .. "|" .. tostring(location.status))

local queued = false
local loaded = false
local return_queued = false
local returned = false
local return_ticks = 0
local return_town
local registered_native_map_id
game.events.subscribe("game.scene.entered", function(scene)
  local state = assert(game.debug.inspect())
  if loaded and return_queued then
    assert(not returned and scene.scene_id == "town")
    local towns = assert(game.locations.list())
    for _, candidate in ipairs(towns) do
      if candidate.kind == "georama" and candidate.native_map_id == state.native_map_id then
        return_town = candidate
        break
      end
    end
    assert(return_town, "return transition did not load the selected native town")
    returned = true
    moonmod.log("info", "MOONFACTORY_RETAIL_LOCATION_RETURNED|" .. return_town.id .. "|" .. state.native_map_id)
    return
  end
  if loaded then return end
  local registered = assert(game.locations.get({id = location.id}))
  registered_native_map_id = registered.native_map_id
  assert(registered.status == "registered" and registered.native_map_id ~= nil)
  if state.native_map_id == registered.native_map_id then
    loaded = true
    moonmod.log("info", "MOONFACTORY_RETAIL_LOCATION_LOADED|" .. registered.id .. "|" .. state.native_map_id)
    local towns = assert(game.locations.list())
    for _, candidate in ipairs(towns) do
      if candidate.kind == "georama" then
        return_town = candidate
        break
      end
    end
    assert(return_town, "the loaded map catalog has no native Georama town")
    return
  end
  if scene.scene_id ~= "town" or queued then return end
  local transition = assert(game.world.transition({id = registered.id}))
  assert(transition.queued and transition.context == "mod_location")
  queued = true
  moonmod.log("info", "MOONFACTORY_RETAIL_LOCATION_QUEUED|" .. transition.native_map_id)
end)

game.events.subscribe("game.tick", function()
  if not loaded or return_queued then return end
  return_ticks = return_ticks + 1
  if return_ticks < 240 then return end
  assert(return_town, "the loaded map catalog has no native Georama town")
  local transition = assert(game.world.transition({id = return_town.id}))
  assert(transition.queued and transition.native_map_id == return_town.native_map_id)
  return_queued = true
  moonmod.log("info", "MOONFACTORY_RETAIL_LOCATION_RETURN_QUEUED|" .. transition.native_map_id)
end)

game.events.subscribe("game.world.location_changed", function(event)
  if not event.previous or event.previous.map_id == event.map_id then return end
  if queued and not return_queued and event.map_id == registered_native_map_id then
    moonmod.log("info", "MOONFACTORY_RETAIL_LOCATION_EVENT|entered|" .. event.map_id)
  elseif return_queued and return_town and event.map_id == return_town.native_map_id then
    moonmod.log("info", "MOONFACTORY_RETAIL_LOCATION_EVENT|returned|" .. event.map_id)
  end
end)
