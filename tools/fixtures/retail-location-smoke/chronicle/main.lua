local override, override_error = game.resources.override({
  path = "resources/mapinfo.cfg",
  game_path = "gedit/s60/mapinfo.cfg"
})
if not override then
  moonmod.log("error", "MOONFACTORY_RETAIL_LOCATION_OVERRIDE_FAILED|" .. tostring(override_error and override_error.message or override_error))
  return {}
end

local location
local queued = false
local loaded = false
local return_queued = false
local return_ticks = 0

local function register_location()
  local registration_error
  location, registration_error = game.locations.register({
    id = "copied-field",
    name = "Retail Copied Field",
    source_map_id = 23
  })
  if not location then
    moonmod.log("error", "MOONFACTORY_RETAIL_LOCATION_REGISTER_FAILED|" ..
                tostring(registration_error and registration_error.message or registration_error))
    return false
  end
  assert(location.id == "chronicle:location:moonfactory.retail-location-probe:copied-field")
  assert(location.native_map_id == 70 and location.status == "registered")
  moonmod.log("info", "MOONFACTORY_RETAIL_LOCATION_REGISTERED|" .. location.id .. "|" .. location.native_map_id)
  return true
end

game.events.subscribe("game.scene.entered", function(scene)
  if scene.scene_id ~= "town" then return end
  local state, state_error = game.debug.inspect()
  if not state then
    moonmod.log("error", "MOONFACTORY_RETAIL_LOCATION_INSPECT_FAILED|" .. tostring(state_error and state_error.message or state_error))
    return
  end
  moonmod.log("info", "MOONFACTORY_RETAIL_LOCATION_SCENE|" .. scene.scene_id .. "|" .. tostring(state.native_map_id))
  if loaded and return_queued and state.native_map_id == 0 then
    moonmod.log("info", "MOONFACTORY_RETAIL_LOCATION_RETURNED|" .. location.id .. "|" .. state.native_map_id)
    return
  end
  if not location and state.native_map_id == 0 then
    if not register_location() then return end
  end
  if not location then return end

  if state.native_map_id == location.native_map_id then
    local world, world_error = game.world.get()
    if not world then
      moonmod.log("error", "MOONFACTORY_RETAIL_LOCATION_WORLD_FAILED|" .. tostring(world_error and world_error.message or world_error))
      return
    end
    moonmod.log("info", "MOONFACTORY_RETAIL_LOCATION_WORLD|" .. tostring(world.context) .. "|" .. tostring(world.location_id))
    local queried, get_error = game.locations.get({id = location.id})
    if not queried then
      moonmod.log("error", "MOONFACTORY_RETAIL_LOCATION_GET_FAILED|" .. tostring(get_error and get_error.message or get_error))
      return
    end
    local listed, list_error = game.locations.list()
    if not listed then
      moonmod.log("error", "MOONFACTORY_RETAIL_LOCATION_LIST_FAILED|" .. tostring(list_error and list_error.message or list_error))
      return
    end
    local found = false
    for _, candidate in ipairs(listed) do
      if candidate.id == location.id then found = true end
    end
    if world.context ~= "location" or world.location_id ~= location.id or
        queried.native_map_id ~= location.native_map_id or not found then
      moonmod.log("error", "MOONFACTORY_RETAIL_LOCATION_STATE_MISMATCH|" .. tostring(world.context) .. "|" ..
                  tostring(world.location_id) .. "|" .. tostring(queried.native_map_id) .. "|" .. tostring(found))
      return
    end
    loaded = true
    moonmod.log("info", "MOONFACTORY_RETAIL_LOCATION_LOADED|" .. location.id .. "|" .. state.native_map_id)
    return
  end

  if state.native_map_id == 0 and not queued then
    local transition = assert(game.world.transition({id = location.id}))
    assert(transition.queued and transition.context == "mod_location")
    assert(transition.native_map_id == location.native_map_id)
    queued = true
    moonmod.log("info", "MOONFACTORY_RETAIL_LOCATION_QUEUED|" .. transition.native_map_id)
  end
end)

game.events.subscribe("game.tick", function()
  if not loaded or return_queued then return end
  return_ticks = return_ticks + 1
  if return_ticks < 240 then return end
  local transition = assert(game.world.transition({id = "chronicle:location:norune-village"}))
  assert(transition.queued and transition.native_map_id == 0)
  return_queued = true
  moonmod.log("info", "MOONFACTORY_RETAIL_LOCATION_RETURN_QUEUED|" .. transition.native_map_id)
end)

game.events.subscribe("game.world.location_changed", function(event)
  if not location or not event.previous or event.previous.map_id == event.map_id then return end
  if queued and not return_queued and event.map_id == location.native_map_id then
    moonmod.log("info", "MOONFACTORY_RETAIL_LOCATION_EVENT|entered|" .. event.map_id)
  elseif return_queued and event.map_id == 0 then
    moonmod.log("info", "MOONFACTORY_RETAIL_LOCATION_EVENT|returned|" .. event.map_id)
  end
end)

return {}
