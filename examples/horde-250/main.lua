-- Horde 250: test for the raised Chronicle monster limit.
-- Enter any dungeon floor; after a short wait 250 monsters appear in a spiral
-- around you and all of them stay awake (entities.set_active_limit).

local TARGET = 250
local SPACING = 12        -- game units between monsters
local WAIT_FRAMES = 120   -- let the floor finish loading first

local done = false
local floor_frames = 0
local spawned = 0
local first_handle = nil
local registered = {}

local function log(message)
  moonmod.log("info", "HORDE|" .. message)
end

-- Find a native monster template this floor has loaded, and register one
-- enemy variant from it (spawning needs a template the floor already loaded).
local function horde_character()
  for monster_id = 0, 166 do
    local model = game.models.resolve({monster_id = monster_id})
    if model and model.loaded_on_current_floor then
      if registered[monster_id] then return registered[monster_id], model.model end
      local character, err = game.characters.register({
        id = "horde-" .. monster_id,
        kind = "enemy",
        name = "Horde " .. monster_id,
        template_monster_id = monster_id,
        assets = {},
      })
      if character then registered[monster_id] = character.id; return character.id, model.model end
      return nil, "register failed for template " .. monster_id .. ": " .. tostring(err and err.message)
    end
  end
  return nil, "no native template is loaded on this floor"
end

local function spiral(index, center)
  -- Golden-angle spiral keeps neighbours about SPACING apart.
  local angle = index * 2.39996
  local radius = SPACING * math.sqrt(index + 4)
  return {x = center.x + radius * math.cos(angle), y = center.y, z = center.z + radius * math.sin(angle)}
end

local function spawn_horde(center, character, model)
  local limit, limit_err = game.entities.set_active_limit({active = TARGET})
  if not limit then
    log("set_active_limit failed: " .. tostring(limit_err and limit_err.message))
    return true
  end


  spawned = 0
  first_handle = nil
  for index = 0, TARGET - 1 do
    local ok, err = game.characters.spawn({character = character, position = spiral(index, center)})
    if not ok then
      if spawned > 0 or index > 0 then log("stopped at " .. spawned .. ": " .. tostring(err and err.message)) end
      break
    end
    if not first_handle then first_handle = ok.entity_handle end
    spawned = spawned + 1
  end
  if spawned == 0 then return false end -- not in control yet; retry next second
  log("awake limit " .. limit.previous .. " -> " .. limit.active .. ", slots " .. limit.slots ..
      ", template model " .. tostring(model))
  log("spawned " .. spawned .. " of " .. TARGET .. " using " .. character)
  game.ui.notify({message = "Horde: " .. spawned .. " monsters"})
  return true
end

moonmod.on("game.tick", function()
  if done then
    -- The floor reloads after its intro scene and clears every actor; spawn again.
    if first_handle and floor_frames % 60 == 0 then
      local entity = game.entities.get({id = first_handle})
      if not entity or entity.status == "expired" then
        log("horde was cleared by a floor reload; spawning again")
        done = false
        floor_frames = 0
      end
    end
    floor_frames = floor_frames + 1
    return
  end
  local world = game.world.get()
  if not world or world.context ~= "dungeon" then
    floor_frames = 0
    return
  end
  floor_frames = floor_frames + 1
  if floor_frames < WAIT_FRAMES then return end
  if floor_frames % 60 ~= 0 then return end
  local player = game.player.get()
  if not player or not player.position then return end
  local character, model = horde_character()
  if not character then
    if floor_frames >= WAIT_FRAMES + 1800 then
      done = true
      local natives = game.entities.query({type = "monster"})
      log("giving up: " .. model .. " (native monsters alive: " .. tostring(natives and natives.count) .. ")")
    end
    return
  end
  done = spawn_horde(player.position, character, model)
end)
