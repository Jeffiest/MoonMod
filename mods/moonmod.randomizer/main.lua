-- Randomizer: a new Dark Cloud from one seed. See README.md.
--
-- A save keeps the seed it first loaded with (stored by save slot), so a playthrough never reshuffles. A new game
-- takes its seed from the Seed setting: today's date (Daily, the same for every player that day: info.get's date
-- is the UTC calendar day), the Fixed seed, or a random one. Everything is drawn from one generator seeded with it,
-- in a fixed order, so the same seed gives the same game on any machine.

local ID = "moonmod.randomizer"

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
local function notify(message, frames) try(game.ui.notify, {message = message, duration_frames = frames or 300}) end

-- A small generator with integer state, so every platform draws the same numbers (xorshift32).
local M32 = 0xFFFFFFFF
local function rng(seed, salt)
  local s = (seed * 2654435761 + (salt or 0) * 40503 + 0x9E3779B9) & M32
  if s == 0 then s = 0x6D2B79F5 end
  local r = {}
  function r.next()
    s = s ~ ((s << 13) & M32)
    s = s ~ (s >> 17)
    s = s ~ ((s << 5) & M32)
    return s
  end
  function r.int(lo, hi) return lo + r.next() % (hi - lo + 1) end
  function r.float() return r.next() / 4294967296 end
  function r.pick(list) return list[r.int(1, #list)] end
  for _ = 1, 4 do r.next() end
  return r
end

-- Share codes: the seed, then a letter for each part that is on and the chest share in tens, as "261104-SWDF5".
-- A friend sets the Fixed seed to the number and the parts to the letters, and plays the same game.
local function share_code(seed)
  local parts = (setting("shops", true) and "S" or "") .. (setting("weapons", true) and "W" or "") ..
                (setting("drops", true) and "D" or "") .. (setting("floors", true) and "F" or "")
  local code = string.format("%06d-%s%d", seed, parts, setting("chests", 50) // 10)
  if setting("weapons", true) and setting("weapon_spread", 30) ~= 30 then code = code .. "w" .. setting("weapon_spread", 30) end
  return code
end

-- Item pools (ps2/include/itemdata.hpp). Story and quest items never move.
local function range(a, b, out) out = out or {}; for i = a, b do out[#out + 1] = i end; return out end
local ATTACH = range(81, 85, range(90, 106, range(111, 120)))
local CONSUMABLE = range(132, 141, range(145, 155, range(159, 180, {183})))
local ATTACH_SET, CONSUMABLE_SET = {}, {}
for _, i in ipairs(ATTACH) do ATTACH_SET[i] = true end
for _, i in ipairs(CONSUMABLE) do CONSUMABLE_SET[i] = true end
local WEAPON_FIRST, WEAPON_LAST = 258, 376
local MONSTER_LAST = 160

-- The seed for this save ----------------------------------------------------------------------------------------------
local function today_seed()
  local info = try(game.info.get)
  local d = info and info.date
  if type(d) == "table" and d.year then return (d.year % 100) * 10000 + d.month * 100 + d.day end
  return nil
end
local function new_seed()
  local mode = setting("seed_mode", "Daily")
  if mode == "Fixed" then return setting("seed", 1) end
  if mode == "Daily" then
    local s = today_seed()
    if s then return s end
    moonmod.log("warn", "this engine has no date in info.get: Daily falls back to the Fixed seed")
    return setting("seed", 1)
  end
  return math.random(0, 999999)
end

local slot_key, seed = nil, nil
local applied = {}   -- what took effect this load, for Check
local visits = {}    -- floor visits this save, so each visit's floor follows the seed too

local function slots() local d = moonmod.storage.get("slots"); return type(d) == "table" and d or {} end

-- Shops ---------------------------------------------------------------------------------------------------------------
-- Each shop keeps its size; weapons are drawn from every shop's weapons and goods from every shop's goods, so a shop
-- may sell a late game sword in Norune.
local function shuffle_shops(r)
  local lists, weapons, goods = {}, {}, {}
  for shop = 0, 17 do
    local got = try(game.shops.get, {shop_no = shop})
    if not (got and type(got.items) == "table") then return 0 end
    lists[shop] = {}
    for _, e in ipairs(got.items) do
      local no = tonumber(e.item_no)
      if no then
        lists[shop][#lists[shop] + 1] = no
        if no >= WEAPON_FIRST then weapons[#weapons + 1] = no else goods[#goods + 1] = no end
      end
    end
  end
  local done = 0
  for shop = 0, 17 do
    local items = {}
    for i, no in ipairs(lists[shop]) do
      items[i] = (no >= WEAPON_FIRST and #weapons > 0) and r.pick(weapons) or (#goods > 0 and r.pick(goods) or no)
    end
    if #items > 0 and try(game.shops.set_items, {shop_no = shop, items = items}) then done = done + 1 end
  end
  return done
end

-- Weapons -------------------------------------------------------------------------------------------------------------
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function shuffle_weapons(r)
  local spread = setting("weapon_spread", 30) / 100
  local done = 0
  for no = WEAPON_FIRST, WEAPON_LAST do
    local w = try(game.weapons.get, "chronicle:weapon:" .. no)
    local st = w and w.stats
    -- Draw for every number, used or not, so the sequence never depends on what the game reports.
    local f = {}
    for i = 1, 5 do f[i] = 1 + (r.float() * 2 - 1) * spread end
    if st and (st.attack or 0) > 0 then
      local request = {id = no,
        attack = clamp(math.floor(st.attack * f[1] + 0.5), 1, 32767),
        endurance = clamp(math.floor((st.endurance or 0) * f[2] + 0.5), 0, 32767),
        speed = clamp(math.floor((st.speed or 0) * f[3] + 0.5), 0, 32767),
        magic = clamp(math.floor((st.magic or 0) * f[4] + 0.5), 0, 32767),
        durability = clamp(math.floor((st.durability or 1) * f[5] + 0.5), 1, 32767)}
      local caps = w.stat_caps
      if caps and caps.attack then request.attack_max = clamp(math.floor(caps.attack * f[1] + 0.5), request.attack, 32767) end
      if try(game.weapons.definition_set, request) then done = done + 1 end
    end
  end
  return done
end

-- Drops ---------------------------------------------------------------------------------------------------------------
local function shuffle_drops(r)
  local done = 0
  for id = 0, MONSTER_LAST do
    local rare, steal = r.pick(CONSUMABLE), (r.float() < 0.3) and r.pick(ATTACH) or r.pick(CONSUMABLE)
    local got = try(game.dungeons.loot_get, {monster_id = id})
    if got then
      local request = {monster_id = id}
      if (got.rare_item or -1) >= 0 then request.rare_item = rare end
      if (got.steal_item or -1) >= 0 then request.steal_item = steal end
      if (request.rare_item or request.steal_item) and try(game.dungeons.loot_override, request) then done = done + 1 end
    end
  end
  return done
end

-- Loading a save ------------------------------------------------------------------------------------------------------
local function apply()
  applied = {}
  if not seed then return end
  -- Each part draws from its own stream, so turning one off doesn't change the others.
  if setting("shops", true) then applied.shops = shuffle_shops(rng(seed, 1)) end
  if setting("weapons", true) then applied.weapons = shuffle_weapons(rng(seed, 2)) end
  if setting("drops", true) then applied.drops = shuffle_drops(rng(seed, 3)) end
end

local in_sandbox = false
local function load_slot()
  if in_sandbox then return end
  local identity = try(game.save.slot_id)
  local player = try(game.player.get)
  local key = identity and identity.slot_id and (tostring(identity.slot_id) .. ":" .. tostring(identity.slot_generation)) or nil
  if not key and player then key = "unsaved" end
  if key == slot_key then return end
  local previous = slot_key
  slot_key = key
  if not key then seed = nil; return end
  local data = slots()
  -- a new game carries its seed into the slot it is first saved to
  if previous == "unsaved" and key ~= "unsaved" and type(data[key]) ~= "table" and type(data.unsaved) == "table" then
    data[key], data.unsaved = data.unsaved, nil
  end
  local entry = type(data[key]) == "table" and data[key] or nil
  local fresh = entry == nil
  if fresh then entry = {seed = new_seed(), visits = {}} end
  data[key] = entry
  moonmod.storage.set("slots", data)
  seed, visits = entry.seed, type(entry.visits) == "table" and entry.visits or {}
  entry.visits = visits
  apply()
  notify(string.format("Randomizer seed %d (code %s)%s", seed, share_code(seed), fresh and ": a new shuffle" or ""), 360)
end

local function save_visits()
  if not slot_key then return end
  local data = slots()
  if type(data[slot_key]) == "table" then data[slot_key].visits = visits; moonmod.storage.set("slots", data) end
end

-- Floors and chests ---------------------------------------------------------------------------------------------------
moonmod.on("game.dungeon.generating", function(e)
  if in_sandbox or not seed or not setting("floors", true) or not e or e.back_floor or e.prebuild then return end
  local key = tostring(e.dungeon_id) .. ":" .. tostring(e.floor_id)
  local n = (visits[key] or 0) + 1
  visits[key] = n
  save_visits()
  local r = rng(seed, 1000 + (tonumber(e.dungeon_id) or 0) * 100 + (tonumber(e.floor_id) or 0))
  for _ = 2, n do r.next() end
  try(game.dungeons.set_seed, {seed = r.next() % 2147483647})
end)

local chest_rng = nil
moonmod.on("game.chest.opened", function(e)
  if in_sandbox or not seed or not e or e.chest == nil then return end
  local item = tonumber(e.item_id) or tonumber(tostring(e.item_id or ""):match("(%d+)$"))
  local pool = item and (ATTACH_SET[item] and ATTACH or CONSUMABLE_SET[item] and CONSUMABLE)
  if not pool then return end
  -- one stream for every chest of the save, by dungeon, floor and chest, so the same chest swaps the same way
  local r = rng(seed, 5000 + (tonumber(e.dungeon_id) or 0) * 1000 + (tonumber(e.floor_id) or 0) * 40 + (tonumber(e.chest) or 0))
  if r.int(1, 100) > setting("chests", 50) then return end
  local swap = r.pick(pool)
  if swap == item then return end
  local removed = try(game.items.remove, {id = "chronicle:item:" .. item, count = 1})
  if removed and (removed.removed or 0) > 0 then
    if not try(game.items.give, {id = "chronicle:item:" .. swap, count = 1}) then
      try(game.items.give, {id = "chronicle:item:" .. item, count = 1}) -- no room: put it back
    end
  end
end)

-- Sessions, ticks, actions --------------------------------------------------------------------------------------------
moonmod.on("game.session.started", function() in_sandbox = true; slot_key, seed = nil, nil end)
moonmod.on("game.session.ended", function() in_sandbox = false end)
do
  local s = try(game.session.get)
  in_sandbox = type(s) == "table" and s.kind == "sandbox"
end

local frame = 0
moonmod.on("game.tick", function()
  frame = frame + 1
  if frame % 30 == 0 then load_slot() end
end)

try(game.ui.register, {id = "check", label = "Seed and Share Code", description = "This save's seed, its share code and what was shuffled"})
moonmod.on("ui.action", function(a)
  if a.id ~= "check" then return end
  load_slot()
  if not seed then notify("Load a game first"); return end
  local parts = {}
  for _, p in ipairs({{"shops", "shops"}, {"weapons", "weapons"}, {"drops", "monsters' drops"}}) do
    local n = applied[p[1]]
    if n and n > 0 then parts[#parts + 1] = n .. " " .. p[2]
    elseif n then parts[#parts + 1] = p[1] .. ": held by another mod" end
  end
  notify(string.format("Seed %d, code %s. %s.", seed, share_code(seed),
    #parts > 0 and table.concat(parts, ", ") or "Nothing shuffled on load"), 600)
end)

load_slot()
moonmod.log("info", "Randomizer ready")
