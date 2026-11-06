-- Modern Cloud: quality of life for Chronicle's story game. Every part is a setting; see README.md.
local REPAIR_POWDER = 177
local REPAIR_AT = 3      -- durability points left when the guard steps in: one hit takes one or two
local CHECK_EVERY = 10   -- frames between weapon and water checks

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if ok then return a, b end
  return nil, a
end

local function setting(id, fallback)
  local v = moonmod.settings.get(id)
  if v == nil then return fallback end
  return v
end

local function notify(message) try(game.ui.notify, {message = message}) end

-- Gauntlet runs and other sandbox sessions are their own game: Modern Cloud sits them out.
local in_sandbox = false

-- Tuning -----------------------------------------------------------------------------------------------------------
local function tuning()
  local thirst = setting("thirst", 50)
  return {
    thirst_drain = math.max(0.25, thirst / 100),
    durability_wear = setting("wear", 75) / 100,
    map_reveal = setting("map_reveal", false) and true or false,
    monster_reveal = setting("monster_reveal", false) and true or false,
    swap_delay = setting("swap_speed", 50) / 100,
    run_speed = setting("run_speed", 100) / 100,
  }
end

local function apply()
  if in_sandbox then try(game.player.tuning_clear); return end
  local ok, err = try(game.player.tuning_set, tuning())
  if not ok then moonmod.log("warn", "tuning_set refused: " .. tostring(type(err) == "table" and err.message or err)) end
end

-- Quick item keys --------------------------------------------------------------------------------------------------
local QUICK = {"1", "2", "3"}
local function bind_keys()
  for i, key in ipairs(QUICK) do
    if setting("quick_keys", true) then try(game.input.bind, {id = "quick_" .. i, keys = {key}})
    else try(game.input.unbind, {id = "quick_" .. i}) end
  end
end

-- Weapon guard ------------------------------------------------------------------------------------------------------
-- The warning steps are kept per weapon (character, slot, item) so each fires once as the weapon wears down, and
-- again after a repair.
local warned = {}
local function weapon_key(p) return p.character .. ":" .. tostring(p.weapon.slot) .. ":" .. tostring(p.weapon.item_no) end

local function guard_weapon(p)
  local mode = setting("weapon_guard", "Repair Powder")
  local w = p.weapon
  if mode == "Off" or not w or not w.id or type(w.durability) ~= "number" or (w.durability_max or 0) <= 0 then return end
  local key = weapon_key(p)
  local now, max = w.durability, w.durability_max
  local function set(value)
    return try(game.weapons.durability_set, {id = w.id, character = p.character, slot = w.slot, durability = value})
  end

  if now <= REPAIR_AT then
    if mode == "Repair Powder" then
      local removed = try(game.items.remove, {id = "chronicle:item:" .. REPAIR_POWDER, count = 1})
      if removed and (removed.removed or 0) > 0 then
        set(max); warned[key] = nil
        notify("Modern Cloud used a Repair Powder: your weapon is mended.")
        return
      end
      if not warned[key] or warned[key] < 3 then
        warned[key] = 3
        notify("Your weapon is about to break, and you have no Repair Powder!")
      end
    elseif mode == "Never break" then
      set(REPAIR_AT + 1)
      if not warned[key] or warned[key] < 3 then
        warned[key] = 3
        notify("Your weapon is worn out. It will not break, but repair it soon.")
      end
    elseif not warned[key] or warned[key] < 3 then
      warned[key] = 3
      notify("Your weapon is about to break!")
    end
    return
  end

  local pct = now * 100 / max
  local warn_at = setting("warn_at", 25)
  if pct < warn_at / 2 then
    if (warned[key] or 0) < 2 then warned[key] = 2; notify(string.format("Your weapon is badly worn (%d%%).", math.floor(pct))) end
  elseif pct < warn_at then
    if (warned[key] or 0) < 1 then warned[key] = 1; notify(string.format("Your weapon is wearing down (%d%%).", math.floor(pct))) end
  elseif warned[key] then
    warned[key] = nil -- repaired some other way
  end
end

-- Water -----------------------------------------------------------------------------------------------------------
local function keep_water(p)
  if setting("thirst", 50) ~= 0 then return end
  if type(p.water) == "number" and type(p.max_water) == "number" and p.water < p.max_water then
    try(game.player.set, {water = p.max_water, character = p.character})
  end
end

-- The tick ---------------------------------------------------------------------------------------------------------
local frame = 0
moonmod.on("game.tick", function()
  frame = frame + 1
  if in_sandbox then return end
  local world = try(game.world.get)
  local in_dungeon = world and world.context == "dungeon"
  if setting("quick_keys", true) then
    for i = 1, 3 do
      local press = try(game.input.consume, {id = "quick_" .. i})
      if press and press.pressed and in_dungeon then
        local ok, err = try(game.items.quick_slot_use, {slot = i})
        if not ok then
          local slot = (try(game.items.quick_slots) or {})[i]
          if slot and not slot.id then notify("Quick slot " .. i .. " is empty.") end
          if err then moonmod.log("info", "quick_slot_use: " .. tostring(type(err) == "table" and err.message or err)) end
        end
      end
    end
  end
  if not in_dungeon or frame % CHECK_EVERY ~= 0 then return end
  local p = try(game.player.get)
  if not p or not p.character then return end
  guard_weapon(p)
  keep_water(p)
end)

-- Sessions, settings, actions --------------------------------------------------------------------------------------
local function set_sandbox(now)
  if now == in_sandbox then return end
  in_sandbox = now
  apply()
end
-- A co-op visit (moonmod.coop) is the story game in the host's world: this mod plays on.
moonmod.on("game.session.started", function(e) if not (type(e) == "table" and e.kind == "visit") then set_sandbox(true) end end)
moonmod.on("game.session.ended", function() set_sandbox(false) end)
moonmod.on("settings.changed", function() bind_keys(); apply() end)

try(game.ui.register, {id = "check", label = "Check", description = "Show what Modern Cloud is doing right now"})
moonmod.on("ui.action", function(action)
  if action.id ~= "check" then return end
  local t = tuning()
  notify(string.format("Thirst x%.2f%s, wear x%.2f, guard: %s, switch x%.2f, walk x%.2f%s%s",
    t.thirst_drain, setting("thirst", 50) == 0 and " (kept full)" or "", t.durability_wear,
    setting("weapon_guard", "Repair Powder"), t.swap_delay, t.run_speed,
    t.map_reveal and ", map shown" or "", t.monster_reveal and ", monsters shown" or ""))
end)

local session = try(game.session.get)
in_sandbox = type(session) == "table" and session.kind == "sandbox"
bind_keys()
apply()
moonmod.log("info", "Modern Cloud ready")
