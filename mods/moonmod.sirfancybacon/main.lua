-- SirFancyBacon Mod Pack (moonmod.sirfancybacon): quality-of-life ideas from SirFancyBacon's Chronicle branches,
-- github.com/SirFancyBacon/Chronicle (qol-pack and floor-select), redone as a MoonMod mod. Credit for the ideas and
-- their rules is his; see README.md for what came from where and what still waits on engine support.

local AUTO_REPAIR_POWDER = 183
local REPAIR_POWDER = 177
local SE_WEAPON_REPAIR = 24
local BREAK_AT = 3      -- durability left when the bag's Auto Repair Powder steps in (a hit takes one or two)
local CHECK_EVERY = 10  -- frames between weapon checks

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if ok then return a, b end
  return nil, a
end
local function setting(id, fallback)
  local v = moonmod.settings.get(id)
  if type(v) ~= type(fallback) then return fallback end
  return v
end
local function notify(message) try(game.ui.notify, {message = message}) end
local function item_id(no) return "chronicle:item:" .. no end

-- The active weapon, when there is one to mend: {id, character, slot, now, max}.
local function active_weapon()
  local p = try(game.player.get)
  local w = type(p) == "table" and p.weapon or nil
  if not w or not w.id or type(w.durability) ~= "number" or (w.durability_max or 0) <= 0 then return nil end
  return {id = w.id, character = p.character, slot = w.slot, now = w.durability, max = w.durability_max}
end
local function mend(w)
  return try(game.weapons.durability_set, {id = w.id, character = w.character, slot = w.slot, durability = w.max})
end
local function take(no)
  local removed = try(game.items.remove, {id = item_id(no), count = 1})
  return type(removed) == "table" and (removed.removed or 0) > 0
end

-- Auto Repair Powder from the bag (qol-pack) --------------------------------------------------------------------------
-- Retail only lets an Auto Repair Powder save a weapon from a quick slot. His rule: with none in a quick slot, one in
-- the bag does the same. One in a quick slot is left to the game.
local function in_quick_slot(no)
  for _, slot in ipairs(try(game.items.quick_slots) or {}) do
    if type(slot) == "table" and slot.item_no == no and (slot.count or 0) > 0 then return true end
  end
  return false
end

local function auto_repair()
  if not setting("auto_repair", true) then return end
  local w = active_weapon()
  if not w or w.now > BREAK_AT or w.now >= w.max then return end
  if in_quick_slot(AUTO_REPAIR_POWDER) then return end
  if not take(AUTO_REPAIR_POWDER) then return end
  mend(w)
  try(game.audio.se_play, {se = SE_WEAPON_REPAIR})
  notify("An Auto Repair Powder from your bag mended your weapon.")
end

-- Repair Powder on a key (qol-pack's "Repair Powder in a quick slot") -----------------------------------------------
try(game.input.bind, {id = "repair", keys = {"T"}})
local function repair_key()
  local key = try(game.input.consume, {id = "repair"})
  if not (key and key.pressed) or not setting("repair_key", true) then return end
  local w = active_weapon()
  if not w then return end
  if w.now >= w.max then notify("Your weapon needs no repair.") return end
  if not take(REPAIR_POWDER) then notify("You have no Repair Powder.") return end
  mend(w)
  try(game.audio.se_play, {se = SE_WEAPON_REPAIR})
  notify("A Repair Powder mended your weapon.")
end

-- The floor list's warning (floor-select) ------------------------------------------------------------------------------
-- Floors whose limit is fixed by the floor itself (floor ids from 0, as the floor list counts them), then the limits a
-- save rolls (dungeons.floor_rules_get). The text is the warning the game gives on arrival, said before going in.
local FIXED = {
  [0] = {[6] = "abs_down", [10] = "xiao_only"},   -- Divine Beast Cave: B7, B11
  [1] = {[3] = "xiao_only", [11] = "goro_only"},  -- Wise Owl Forest: 4, 12
  [3] = {[4] = "goro_only", [12] = "ungaga_only"}, -- Sun and Moon Temple: 5, 13
}
local ONLY = {toan_only = "Toan", xiao_only = "Xiao", goro_only = "Goro", ruby_only = "Ruby",
              ungaga_only = "Ungaga", osmond_only = "Osmond"}
local function warning_for(dungeon, floor)
  local limit = FIXED[dungeon] and FIXED[dungeon][floor]
  if not limit then
    local rules = try(game.dungeons.floor_rules_get, {dungeon_id = dungeon, floor_id = floor})
    limit = type(rules) == "table" and rules.limit_zone_name or nil
  end
  if not limit or limit == "none" then return nil end
  if ONLY[limit] then return "! Only " .. ONLY[limit] .. " can go on this floor" end
  if limit == "abs_down" then return "! Weapons can't be changed on this floor" end
  if limit == "thirst" then return "! Thirst comes faster on this floor" end
  return "! This floor has a limit"
end

local shown = nil -- "dungeon:floor" the warning is shown for, or false for none
local function floor_warning()
  local s = setting("limit_warning", true) and try(game.dungeons.selection) or nil
  local key = type(s) == "table" and (s.dungeon_id .. ":" .. s.floor_id) or nil
  if key == shown then return end
  shown = key
  local text = key and warning_for(s.dungeon_id, s.floor_id)
  if text then try(game.render.layer_register, {id = "floor_limit", text = text})
  else try(game.render.layer_remove, {id = "floor_limit"}) end
end

moonmod.on("game.tick", function(e)
  local frame = type(e) == "table" and e.frame or 0
  repair_key()
  if frame % CHECK_EVERY == 0 then
    auto_repair()
    floor_warning()
  end
end)

-- For the tests.
return {warning_for = warning_for}
