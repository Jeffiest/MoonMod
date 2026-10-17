-- Dungeon Expeditions is a Chronicle-only example package.
-- Maze mode tunes future native procedural floors. Horde mode keeps more native enemies awake.
-- Run rewards are paid only when the player banks the run.

local STORE_KEY = "expedition"
local MODE_MAZE = "maze"
local MODE_HORDE = "horde"
local MAZE_CONTRACT_FLOORS = 4
local HORDE_CONTRACT_KILLS = 25

local function notify(message, frames)
  local result, err = game.ui.notify({message = message, duration_frames = frames or 300})
  if not result then
    moonmod.log("warning", "Dungeon Expeditions notice failed: " .. tostring(err and err.message or "unknown error"))
  end
end

local function api(label, callback, argument)
  local result, err
  if argument == nil then
    result, err = callback()
  else
    result, err = callback(argument)
  end
  if not result then
    moonmod.log("warning", label .. " failed: " .. tostring(err and err.message or "unknown error"))
  end
  return result
end

local function read_run()
  local run = moonmod.storage.get(STORE_KEY)
  if type(run) ~= "table" or run.version ~= 1 then
    return {version = 1, active = false, floors = {}, kills = 0}
  end
  if type(run.floors) ~= "table" then run.floors = {} end
  if type(run.kills) ~= "number" then run.kills = 0 end
  return run
end

local run = read_run()

local function save_run()
  local ok, err = moonmod.storage.set(STORE_KEY, run)
  if not ok then
    moonmod.log("warning", "Could not save expedition state: " .. tostring(err and err.message or "unknown error"))
  end
end

local function setting(id, fallback)
  local value = moonmod.settings.get(id)
  if type(value) ~= "number" then return fallback end
  return math.floor(value)
end

local function floor_count()
  local count = 0
  for _ in pairs(run.floors) do count = count + 1 end
  return count
end

local function mode_label(mode)
  return mode == MODE_HORDE and "Horde" or "Maze"
end

local function update_contract()
  if not run.active or run.contract_complete then return end
  local complete = false
  if run.mode == MODE_HORDE then
    complete = run.kills >= HORDE_CONTRACT_KILLS
  else
    complete = floor_count() >= MAZE_CONTRACT_FLOORS
  end
  if complete then
    run.contract_complete = true
    save_run()
    notify(mode_label(run.mode) .. " contract complete! Bank the expedition in the manager.")
  end
end

local function track_floor(location)
  if not run.active or location.context ~= "dungeon" then return end
  if type(location.dungeon_id) ~= "number" or type(location.floor_id) ~= "number" then return end
  local key = tostring(location.dungeon_id) .. ":" .. tostring(location.floor_id)
  if not run.floors[key] then
    run.floors[key] = true
    run.last_dungeon = location.dungeon_id
    run.last_floor = location.floor_id
    save_run()
    update_contract()
  end
end

local function apply_mode()
  if not run.active then return end
  if run.mode == MODE_MAZE then
    local rooms = math.max(2, math.min(64, setting("maze_rooms", 24)))
    local area = math.max(8, math.min(46, setting("maze_area", 40)))
    area = math.max(area, 4)
    api("dungeons.set_layout", game.dungeons.set_layout, {
      rooms = rooms,
      area = area,
      room_min = 2,
      room_max = 3
    })
  elseif run.mode == MODE_HORDE then
    -- Large native rooms and a higher awake limit create a denser simultaneous fight.
    api("dungeons.set_layout", game.dungeons.set_layout, {
      rooms = 10,
      area = 46,
      room_min = 4,
      room_max = 6
    })
    if run.previous_active_limit == nil then
      local changed = api("entities.set_active_limit", game.entities.set_active_limit, {
        active = setting("horde_active_limit", 16)
      })
      if changed then run.previous_active_limit = changed.previous end
    else
      api("entities.set_active_limit", game.entities.set_active_limit, {
        active = setting("horde_active_limit", 16)
      })
    end
  end
end

local function restore_runtime()
  api("dungeons.set_layout reset", game.dungeons.set_layout, {})
  if run.previous_active_limit ~= nil then
    api("entities.set_active_limit restore", game.entities.set_active_limit, {
      active = run.previous_active_limit
    })
  end
end

local function bank_run()
  if not run.active then
    notify("There is no active expedition to bank.")
    return
  end

  local floors = floor_count()
  local reward = setting("base_reward", 100)
    + floors * setting("per_floor_reward", 75)
    + run.kills * setting("per_kill_reward", 2)
  if run.contract_complete then
    reward = reward + setting("contract_bonus", 500)
  end
  reward = math.max(1, math.min(32767, reward))

  local credit = api("economy.add", game.economy.add, {amount = reward})
  if not credit then
    notify("The expedition could not be banked. See the MoonFactory log.")
    return
  end

  local summary = mode_label(run.mode) .. " expedition banked: "
    .. tostring(floors) .. " floors, " .. tostring(run.kills) .. " defeats, +"
    .. tostring(credit.added or reward) .. " Gilda."
  restore_runtime()
  run = {version = 1, active = false, floors = {}, kills = 0}
  save_run()
  notify(summary, 480)
end

local function abandon_run()
  if not run.active then
    notify("There is no active expedition to abandon.")
    return
  end
  restore_runtime()
  run = {version = 1, active = false, floors = {}, kills = 0}
  save_run()
  notify("Expedition abandoned. No reward was banked.")
end

local function start_run(mode)
  if run.active then
    notify("An expedition is already active. Bank or abandon it first.")
    return
  end
  run = {
    version = 1,
    active = true,
    mode = mode,
    floors = {},
    kills = 0,
    contract_complete = false,
    bank_on_return = false
  }

  local location = api("world.get", game.world.get)
  if location and location.context == "dungeon" then
    run.entered_dungeon = true
    track_floor(location)
  end
  apply_mode()
  save_run()

  if mode == MODE_MAZE then
    notify("Maze Expedition started. Reach 4 distinct floors to complete its contract.")
  else
    notify("Horde Expedition started. Defeat 25 enemies to complete its contract.")
  end
end

assert(game.ui.register({
  id = "start-maze",
  label = "Start Maze Expedition",
  description = "Begin a run with a denser native maze layout."
}))
assert(game.ui.register({
  id = "start-horde",
  label = "Start Horde Expedition",
  description = "Begin a run with more enemies active at once."
}))
assert(game.ui.register({
  id = "bank-expedition",
  label = "Bank Expedition",
  description = "Bank the run now, or on your next return to town."
}))
assert(game.ui.register({
  id = "abandon-expedition",
  label = "Abandon Expedition",
  description = "End the active run without its Gilda reward."
}))

moonmod.on("ui.action", function(action)
  if action.id == "start-maze" then
    start_run(MODE_MAZE)
  elseif action.id == "start-horde" then
    start_run(MODE_HORDE)
  elseif action.id == "bank-expedition" then
    if not run.active then
      notify("There is no active expedition to bank.")
      return
    end
    local location = api("world.get", game.world.get)
    if location and location.context == "dungeon" then
      run.bank_on_return = true
      save_run()
      notify("Run locked for banking. Return to town to collect your Gilda.")
    elseif run.entered_dungeon then
      bank_run()
    else
      notify("Enter a dungeon before banking this expedition.")
    end
  elseif action.id == "abandon-expedition" then
    abandon_run()
  end
end)

moonmod.on("game.enemy_defeated", function()
  if not run.active then return end
  run.kills = run.kills + 1
  save_run()
  update_contract()
end)

moonmod.on("game.world.location_changed", function(location)
  if not run.active or type(location) ~= "table" then return end
  if location.context == "dungeon" then
    run.entered_dungeon = true
    track_floor(location)
    apply_mode()
    save_run()
    return
  end

  if location.context == "town" and location.previous
      and location.previous.context == "dungeon" then
    restore_runtime()
    if run.bank_on_return then
      bank_run()
    else
      notify("Back in town. Your expedition is still active; bank it or descend again.")
    end
  end
end)

moonmod.on("runtime.loaded", function()
  if not run.active then return end
  local location = api("world.get", game.world.get)
  if location and location.context == "dungeon" then
    run.entered_dungeon = true
    track_floor(location)
    apply_mode()
    save_run()
  end
end)

moonmod.on("runtime.unloaded", function()
  -- The native floor layout and awake limit are global runtime settings.
  -- Restore them even when this package is disabled mid-run.
  restore_runtime()
end)

moonmod.log("info", "Dungeon Expeditions loaded for Chronicle.")
