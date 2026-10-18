local enabled = false
local chord_down = false

local function setting(id, fallback)
  local value = moonmod.settings.get(id)
  return type(value) == "number" and value or fallback
end

local function bind()
  assert(game.input.bind({id = "town_overhead_key", keys = {moonmod.settings.get("town_camera_key") or "O"}}))
  assert(game.input.bind({id = "town_overhead_l1", keys = {"Gamepad:leftshoulder"}}))
  assert(game.input.bind({id = "town_overhead_l3", keys = {"Gamepad:leftstick"}}))
end
bind()
moonmod.on("settings.changed", bind)

local function town_context(world)
  return world and world.context == "georama"
end

local function set_enabled(value, notify)
  value = not not value
  if enabled == value then return true end
  local changed, err = game.render.town_camera_set({
    enabled = value,
    height = setting("camera_height", 90),
    back = setting("camera_back", 22)
  })
  if not changed then
    game.ui.notify({message = "Town camera unavailable: " .. tostring(type(err) == "table" and err.message or err)})
    return false
  end
  enabled = value
  if notify then game.ui.notify({message = enabled and "Overhead town camera" or "Town camera restored"}) end
  return true
end

game.ui.register({
  id = "toggle_town_camera",
  label = "Toggle Overhead Town Camera",
  description = "Toggle the overhead camera while walking in a town"
})

moonmod.on("ui.action", function(action)
  if action.id ~= "toggle_town_camera" then return end
  if not town_context(game.world.get()) then
    game.ui.notify({message = "Enter a town to use the overhead camera"})
    return
  end
  set_enabled(not enabled, true)
end)

moonmod.on("game.tick", function()
  local world = game.world.get()
  if not town_context(world) then
    if enabled then set_enabled(false, false) end
    chord_down = false
    game.input.consume({id = "town_overhead_key"})
    game.input.consume({id = "town_overhead_l1"})
    game.input.consume({id = "town_overhead_l3"})
    return
  end

  local key = game.input.consume({id = "town_overhead_key"})
  local l1 = game.input.state({id = "town_overhead_l1"})
  local l3 = game.input.state({id = "town_overhead_l3"})
  local chord = l1 and l1.down and l3 and l3.down or false
  if (key and key.pressed) or (chord and not chord_down) then set_enabled(not enabled, true) end
  chord_down = chord
end)

moonmod.log("info", "Expanded Town Camera initialized (O or L1+L3)")
